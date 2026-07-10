//! src/lib.rs — Omni-Mind P2P Knowledge Swarm
//!
//! Provides gossip-based axiom broadcasting between Omni-Mind nodes.
//! Each node runs a Zig core (via FFI) for actual reasoning, and
//! uses this Rust crate for networking + cryptography.

pub mod protocol;
pub mod crawler;
pub mod ffi;
pub mod network;
pub mod web;
pub mod internet;

pub use protocol::{GossipMessage, HandleResult, SwarmNode};
pub use crawler::{LogicalCrawler, KnowledgeGap, AxiomCandidate, CrawlerStats};
pub use network::{NetworkedNode, NetworkStats};
pub use internet::{
    InternetFact, AggregatedKnowledge,
    search_wikipedia, search_all_sources, search_source, list_sources,
    fact_to_axiom_text, aggregated_to_axiom,
};

/// Initialize the swarm. Must be called once at startup.
pub fn init() -> Result<(), SwarmError> {
    log::info!("Omni-Mind Swarm initializing");
    Ok(())
}

#[derive(Debug)]
pub enum SwarmError {
    NetworkError(String),
    CryptoError(String),
    CoreError(i32),
}

impl std::fmt::Display for SwarmError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NetworkError(s) => write!(f, "network error: {}", s),
            Self::CryptoError(s) => write!(f, "crypto error: {}", s),
            Self::CoreError(c) => write!(f, "core error: {}", c),
        }
    }
}

impl std::error::Error for SwarmError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn swarm_init_succeeds() {
        assert!(init().is_ok());
    }
}
