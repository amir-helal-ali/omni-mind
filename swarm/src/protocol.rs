//! src/protocol.rs — Gossip message format and handler.
//!
//! When a node learns a new axiom (from the Crawler or a user),
//! it broadcasts a GossipMessage to its peers. Peers verify the
//! signature, check proof-of-stake, then forward to 3 random peers.

use serde::{Deserialize, Serialize};
use std::collections::HashSet;

/// A gossip message — broadcast when a node learns a new axiom.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct GossipMessage {
    /// Hash of axiom content (blake3)
    pub rule_id: u64,
    /// Originator's node ID
    pub source_node: u64,
    /// Which domain (physics, bio, ...)
    pub domain: u8,
    /// Time-to-live, decremented per hop
    pub ttl: u8,
    /// Serialized axiom text (UTF-8)
    pub payload: Vec<u8>,
    /// Source node's signature over payload (simplified: blake3 hash)
    pub signature: Vec<u8>,
    /// Proof-of-axiom-stake (anti-Sybil)
    pub stake_proof: u64,
}

/// Result of handling a gossip message.
#[derive(Debug, PartialEq)]
pub enum HandleResult {
    Accepted,
    Duplicate,
    Rejected(&'static str),
}

/// A Swarm node — owns a peer set and tracks seen messages.
pub struct SwarmNode {
    pub node_id: u64,
    pub peers: Vec<u64>,
    pub seen_rules: HashSet<u64>,
    pub stake: u64,
}

impl SwarmNode {
    pub fn new(node_id: u64) -> Self {
        Self {
            node_id,
            peers: Vec::new(),
            seen_rules: HashSet::new(),
            stake: 0,
        }
    }

    /// Handle an incoming gossip message.
    pub fn handle(&mut self, msg: &GossipMessage) -> HandleResult {
        // 1. Verify TTL
        if msg.ttl == 0 {
            return HandleResult::Rejected("ttl expired");
        }

        // 2. Deduplicate
        if self.seen_rules.contains(&msg.rule_id) {
            return HandleResult::Duplicate;
        }

        // 3. Verify signature (simplified — real impl uses Ed25519)
        if msg.signature.is_empty() {
            return HandleResult::Rejected("missing signature");
        }

        // 4. Verify proof-of-stake (Sybil resistance)
        if msg.stake_proof < 10 && msg.ttl > 2 {
            return HandleResult::Rejected("insufficient stake for high TTL");
        }

        // 5. Mark as seen
        self.seen_rules.insert(msg.rule_id);

        HandleResult::Accepted
    }

    /// Broadcast a new axiom to all peers.
    pub fn broadcast_new_axiom(
        &mut self,
        domain: u8,
        axiom_text: &str,
        signature: Vec<u8>,
    ) -> GossipMessage {
        // Compute blake3 hash of the axiom text as rule_id.
        let hash = blake3::hash(axiom_text.as_bytes());
        let rule_id = u64::from_le_bytes(hash.as_bytes()[0..8].try_into().unwrap());

        // Increment our stake (we contributed a rule).
        self.stake += 1;
        self.seen_rules.insert(rule_id);

        GossipMessage {
            rule_id,
            source_node: self.node_id,
            domain,
            ttl: 8,
            payload: axiom_text.as_bytes().to_vec(),
            signature,
            stake_proof: self.stake,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handle_accepts_valid_message() {
        let mut node = SwarmNode::new(1);
        let msg = GossipMessage {
            rule_id: 0xdeadbeef,
            source_node: 2,
            domain: 0,
            ttl: 8,
            payload: b"test axiom".to_vec(),
            signature: vec![0xaa; 64],
            stake_proof: 100,
        };
        assert_eq!(node.handle(&msg), HandleResult::Accepted);
    }

    #[test]
    fn handle_rejects_duplicate() {
        let mut node = SwarmNode::new(1);
        let msg = GossipMessage {
            rule_id: 0xdeadbeef,
            source_node: 2,
            domain: 0,
            ttl: 8,
            payload: b"test".to_vec(),
            signature: vec![0xaa; 64],
            stake_proof: 100,
        };
        node.handle(&msg);
        assert_eq!(node.handle(&msg), HandleResult::Duplicate);
    }

    #[test]
    fn handle_rejects_low_stake_high_ttl() {
        let mut node = SwarmNode::new(1);
        let msg = GossipMessage {
            rule_id: 0x1,
            source_node: 2,
            domain: 0,
            ttl: 8,
            payload: b"test".to_vec(),
            signature: vec![0xaa; 64],
            stake_proof: 5,
        };
        assert_eq!(node.handle(&msg), HandleResult::Rejected("insufficient stake for high TTL"));
    }

    #[test]
    fn broadcast_increments_stake() {
        let mut node = SwarmNode::new(1);
        assert_eq!(node.stake, 0);
        let _ = node.broadcast_new_axiom(0, "test axiom", vec![0xaa; 64]);
        assert_eq!(node.stake, 1);
    }

    #[test]
    fn broadcast_deduplicates_same_axiom() {
        let mut node = SwarmNode::new(1);
        let m1 = node.broadcast_new_axiom(0, "test axiom", vec![0xaa; 64]);
        let m2 = node.broadcast_new_axiom(0, "test axiom", vec![0xbb; 64]);
        assert_eq!(m1.rule_id, m2.rule_id); // same hash for same text
    }
}
