//! src/bin/node.rs — Standalone Swarm node binary with real TCP networking.
//!
//! Run with: cargo run --bin omni-swarm-node [-- --port N --peers ADDR1,ADDR2]
//!
//! Boots a single Omni-Mind node:
//!   - Zig core (via FFI) for reasoning
//!   - TCP listener for incoming gossip
//!   - Outbound connections to known peers

use omni_swarm::{init, NetworkedNode, LogicalCrawler, KnowledgeGap, CrawlerStats};
use omni_swarm::ffi;
use std::net::{SocketAddr, Ipv4Addr};
use std::thread;
use std::time::Duration;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    log::info!("Starting Omni-Mind Swarm Node");

    // Parse args
    let args: Vec<String> = std::env::args().collect();
    let port: u16 = parse_arg(&args, "--port", 18080);
    let peers_str: String = parse_arg(&args, "--peers", String::new());

    let listen_addr = SocketAddr::new(Ipv4Addr::new(0, 0, 0, 0).into(), port);

    // Initialize the swarm
    init().expect("swarm init failed");

    // Run Zig FFI on a thread with a large stack
    let core_thread = thread::Builder::new()
        .name("omni-core".into())
        .stack_size(64 * 1024 * 1024)
        .spawn(run_core)
        .expect("failed to spawn core thread");

    // Create the networked node
    let node = NetworkedNode::new(1, listen_addr);

    // Add peers from CLI
    if !peers_str.is_empty() {
        for peer_str in peers_str.split(',') {
            if let Ok(peer_addr) = peer_str.trim().parse::<SocketAddr>() {
                node.add_peer(peer_addr);
                log::info!("Added peer: {}", peer_addr);
            }
        }
    }

    // Start the TCP listener
    let listener_handle = node.start_listener();

    // Demo: broadcast a few axioms
    let demo_axioms = [
        (0u8, "energy is conserved"),
        (5u8, "AI processes information"),
        (2u8, "cells are the basic unit of life"),
    ];
    for (domain, text) in &demo_axioms {
        let msg = node.broadcast_new_axiom(*domain, text);
        log::info!("Broadcast: rule_id={:#x}, domain={}, text=\"{}\"", msg.rule_id, domain, text);
        thread::sleep(Duration::from_millis(100));
    }

    // Run a crawler in the background
    let mut crawler = LogicalCrawler::new().offline();
    crawler.report_gap(KnowledgeGap {
        domain: 0,
        gap_signature: 0xdeadbeef,
        priority: 0.9,
        query_text: Some("quantum machine learning".to_string()),
    });

    // Forage for new knowledge
    if let Some(candidate) = crawler.forage_once() {
        log::info!("Crawler discovered: {} (confidence: {:.2}, source: {})",
            candidate.relation, candidate.confidence, candidate.source);
    }

    // Print stats periodically
    let stats_node = node.stats();
    let crawler_stats: CrawlerStats = crawler.stats();
    log::info!("Network: {} msgs received, {} sent, {} peers",
        stats_node.messages_received, stats_node.messages_sent, stats_node.peer_count);
    log::info!("Crawler: {} gaps, {} probes, {} discovered",
        crawler_stats.gaps_pending, crawler_stats.probes_registered, crawler_stats.candidates_discovered);

    log::info!("Node running on port {}. Press Ctrl+C to stop.", port);

    // Keep running
    core_thread.join().ok();
    listener_handle.join().ok();
}

fn parse_arg<T: std::str::FromStr>(args: &[String], flag: &str, default: T) -> T {
    for (i, a) in args.iter().enumerate() {
        if a == flag {
            if let Some(val) = args.get(i + 1) {
                if let Ok(v) = val.parse::<T>() {
                    return v;
                }
            }
        }
    }
    default
}

fn run_core() {
    let rc = ffi::bootstrap();
    if rc != 0 {
        log::error!("Failed to bootstrap Zig core (rc={})", rc);
        return;
    }
    log::info!("Zig core bootstrapped via FFI");

    let stats = ffi::stats();
    log::info!("Core: {} nodes, {} edges, {} axioms, {}/{} bytes ({:.1}%)",
        stats.node_count, stats.edge_count, stats.axiom_count,
        stats.bytes_used, stats.bytes_budget,
        (stats.bytes_used as f64 / stats.bytes_budget as f64) * 100.0);

    match ffi::safe_query("Can quantum mechanics improve AI?") {
        Ok(answer) => log::info!("FFI query: {}", answer),
        Err(e) => log::error!("FFI query failed: {}", e),
    }

    let _ = ffi::shutdown();
}
