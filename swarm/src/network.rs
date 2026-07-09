//! src/network.rs — Real TCP-based P2P networking for the Knowledge Swarm.
//!
//! Each node listens on a TCP port and also connects to known peers.
//! Gossip messages are serialized as length-prefixed JSON.
//! This is a minimal, dependency-free alternative to libp2p.

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream, SocketAddr};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::Duration;

use crate::protocol::{GossipMessage, HandleResult, SwarmNode};
use serde::{Serialize, Deserialize};

/// A networked swarm node — owns a listener + peer connections.
pub struct NetworkedNode {
    pub node: Arc<Mutex<SwarmNode>>,
    pub listen_addr: SocketAddr,
    pub peers: Arc<Mutex<Vec<SocketAddr>>>,
    pub messages_received: Arc<AtomicU64>,
    pub messages_sent: Arc<AtomicU64>,
}

/// Wire format: 4-byte big-endian length prefix + JSON payload.
#[derive(Serialize, Deserialize)]
struct WireMessage {
    msg: GossipMessage,
}

impl NetworkedNode {
    /// Create a new networked node listening on the given address.
    pub fn new(node_id: u64, listen_addr: SocketAddr) -> Self {
        Self {
            node: Arc::new(Mutex::new(SwarmNode::new(node_id))),
            listen_addr,
            peers: Arc::new(Mutex::new(Vec::new())),
            messages_received: Arc::new(AtomicU64::new(0)),
            messages_sent: Arc::new(AtomicU64::new(0)),
        }
    }

    /// Add a peer to connect to.
    pub fn add_peer(&self, addr: SocketAddr) {
        self.peers.lock().unwrap().push(addr);
    }

    /// Start the listener thread. Returns immediately.
    pub fn start_listener(&self) -> thread::JoinHandle<()> {
        let listener = match TcpListener::bind(self.listen_addr) {
            Ok(l) => l,
            Err(e) => {
                log::error!("Failed to bind {}: {}", self.listen_addr, e);
                return thread::spawn(|| {});
            }
        };
        log::info!("Listening on {}", self.listen_addr);

        let node = Arc::clone(&self.node);
        let peers = Arc::clone(&self.peers);
        let rx_count = Arc::clone(&self.messages_received);
        let tx_count = Arc::clone(&self.messages_sent);

        thread::spawn(move || {
            listener.set_nonblocking(true).ok();
            loop {
                match listener.accept() {
                    Ok((stream, addr)) => {
                        log::debug!("Accepted connection from {}", addr);
                        let node = Arc::clone(&node);
                        let peers = Arc::clone(&peers);
                        let rx = Arc::clone(&rx_count);
                        let tx = Arc::clone(&tx_count);
                        thread::spawn(move || {
                            handle_connection(stream, node, peers, rx, tx);
                        });
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(100));
                    }
                    Err(e) => {
                        log::warn!("Accept error: {}", e);
                        thread::sleep(Duration::from_millis(100));
                    }
                }
            }
        })
    }

    /// Broadcast a gossip message to all known peers.
    pub fn broadcast(&self, msg: &GossipMessage) {
        let wire = WireMessage { msg: msg.clone() };
        let payload = match serde_json::to_vec(&wire) {
            Ok(p) => p,
            Err(e) => {
                log::error!("Serialize error: {}", e);
                return;
            }
        };

        let peers = self.peers.lock().unwrap().clone();
        for peer in peers {
            let payload = payload.clone();
            let tx_count = Arc::clone(&self.messages_sent);
            thread::spawn(move || {
                match TcpStream::connect_timeout(&peer, Duration::from_secs(2)) {
                    Ok(mut stream) => {
                        let len = (payload.len() as u32).to_be_bytes();
                        if stream.write_all(&len).is_ok() && stream.write_all(&payload).is_ok() {
                            tx_count.fetch_add(1, Ordering::Relaxed);
                            log::debug!("Sent gossip to {}", peer);
                        }
                    }
                    Err(e) => {
                        log::debug!("Failed to connect to {}: {}", peer, e);
                    }
                }
            });
        }
    }

    /// Broadcast a new axiom to the network.
    pub fn broadcast_new_axiom(&self, domain: u8, axiom_text: &str) -> GossipMessage {
        let msg = self.node.lock().unwrap().broadcast_new_axiom(
            domain,
            axiom_text,
            vec![0xaa; 64], // simplified signature
        );
        self.broadcast(&msg);
        msg
    }

    /// Get network stats.
    pub fn stats(&self) -> NetworkStats {
        NetworkStats {
            messages_received: self.messages_received.load(Ordering::Relaxed),
            messages_sent: self.messages_sent.load(Ordering::Relaxed),
            peer_count: self.peers.lock().unwrap().len() as u64,
        }
    }
}

#[derive(Debug)]
pub struct NetworkStats {
    pub messages_received: u64,
    pub messages_sent: u64,
    pub peer_count: u64,
}

/// Handle a single TCP connection: read one gossip message, process, forward.
fn handle_connection(
    mut stream: TcpStream,
    node: Arc<Mutex<SwarmNode>>,
    peers: Arc<Mutex<Vec<SocketAddr>>>,
    rx_count: Arc<AtomicU64>,
    tx_count: Arc<AtomicU64>,
) {
    // Read 4-byte length prefix.
    let mut len_buf = [0u8; 4];
    if stream.read_exact(&mut len_buf).is_err() {
        return;
    }
    let len = u32::from_be_bytes(len_buf) as usize;
    if len > 1_048_576 {
        log::warn!("Message too large: {} bytes", len);
        return;
    }

    // Read payload.
    let mut payload = vec![0u8; len];
    if stream.read_exact(&mut payload).is_err() {
        return;
    }

    // Deserialize.
    let wire: WireMessage = match serde_json::from_slice(&payload) {
        Ok(w) => w,
        Err(e) => {
            log::warn!("Deserialize error: {}", e);
            return;
        }
    };

    rx_count.fetch_add(1, Ordering::Relaxed);

    // Process the message.
    let result = node.lock().unwrap().handle(&wire.msg);
    match result {
        HandleResult::Accepted => {
            log::info!("Accepted gossip: rule_id={:#x}", wire.msg.rule_id);

            // Forward to other peers (decrement TTL).
            if wire.msg.ttl > 1 {
                let mut forwarded = wire.msg.clone();
                forwarded.ttl -= 1;
                let forward_payload = match serde_json::to_vec(&WireMessage { msg: forwarded }) {
                    Ok(p) => p,
                    Err(_) => return,
                };
                let peer_list = peers.lock().unwrap().clone();
                for peer in peer_list {
                    let payload = forward_payload.clone();
                    let tx = Arc::clone(&tx_count);
                    thread::spawn(move || {
                        if let Ok(mut s) = TcpStream::connect_timeout(&peer, Duration::from_secs(1)) {
                            let l = (payload.len() as u32).to_be_bytes();
                            if s.write_all(&l).is_ok() && s.write_all(&payload).is_ok() {
                                tx.fetch_add(1, Ordering::Relaxed);
                            }
                        }
                    });
                }
            }
        }
        HandleResult::Duplicate => {
            log::debug!("Duplicate gossip ignored: rule_id={:#x}", wire.msg.rule_id);
        }
        HandleResult::Rejected(reason) => {
            log::warn!("Rejected gossip: {} (rule_id={:#x})", reason, wire.msg.rule_id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;

    #[test]
    fn networked_node_creation() {
        let addr = SocketAddr::new(Ipv4Addr::new(127, 0, 0, 1).into(), 18000);
        let n = NetworkedNode::new(1, addr);
        assert_eq!(n.listen_addr, addr);
        assert_eq!(n.peers.lock().unwrap().len(), 0);
    }

    #[test]
    fn add_peer_works() {
        let addr = SocketAddr::new(Ipv4Addr::new(127, 0, 0, 1).into(), 18001);
        let peer = SocketAddr::new(Ipv4Addr::new(127, 0, 0, 1).into(), 18002);
        let n = NetworkedNode::new(1, addr);
        n.add_peer(peer);
        assert_eq!(n.peers.lock().unwrap().len(), 1);
    }

    #[test]
    fn broadcast_does_not_panic_without_peers() {
        let addr = SocketAddr::new(Ipv4Addr::new(127, 0, 0, 1).into(), 18003);
        let n = NetworkedNode::new(1, addr);
        n.broadcast_new_axiom(0, "test axiom");
        // Should not panic even with no peers.
    }
}
