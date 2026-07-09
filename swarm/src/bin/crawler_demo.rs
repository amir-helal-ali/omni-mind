//! src/bin/crawler_demo.rs — Run the crawler with real HTTP requests.
//!
//! Tests live API connectivity to:
//!   - arXiv (http://export.arxiv.org/api/query)
//!   - Semantic Scholar (https://api.semanticscholar.org)
//!   - Crossref (https://api.crossref.org)
//!
//! Usage: cargo run --bin crawler_demo -- --topic "quantum machine learning"

use omni_swarm::{LogicalCrawler, KnowledgeGap};
use std::env;
use std::time::Duration;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let args: Vec<String> = env::args().collect();
    let topic = parse_arg(&args, "--topic", "quantum machine learning".to_string());
    let max_results = parse_arg(&args, "--max", 5usize);

    log::info!("Omni-Mind Crawler — live API foraging");
    log::info!("Topic: '{}', max results: {}", topic, max_results);

    // Create crawler in ONLINE mode (real HTTP calls).
    let mut crawler = LogicalCrawler::new();

    // Report gaps for multiple domains.
    let domains = [
        (0u8, "physics"),
        (5u8, "computer science"),
        (2u8, "biology"),
    ];

    for (domain, domain_name) in &domains {
        crawler.report_gap(KnowledgeGap {
            domain: *domain,
            gap_signature: 0,
            priority: 0.9,
            query_text: Some(topic.to_string()),
        });
        log::info!("Reported gap: domain={} ({}), topic='{}'", domain, domain_name, topic);
    }

    // Try to forage from each gap.
    log::info!("");
    log::info!("=== Foraging (live HTTP) ===");

    let mut discovered = Vec::new();
    for _ in 0..max_results {
        match crawler.forage_once() {
            Some(candidate) => {
                log::info!("✓ Found: [{}] {} (confidence: {:.2})",
                    candidate.source, candidate.relation, candidate.confidence);
                discovered.push(candidate);
            }
            None => {
                log::info!("(no more candidates — all probes exhausted or offline)");
                break;
            }
        }
    }

    // Print summary.
    log::info!("");
    log::info!("=== Summary ===");
    log::info!("Discovered: {} candidates", discovered.len());
    log::info!("Gaps pending: {}", crawler.stats().gaps_pending);
    log::info!("Probes registered: {}", crawler.stats().probes_registered);

    // If we found candidates, print them in a format suitable for ingestion.
    if !discovered.is_empty() {
        log::info!("");
        log::info!("=== Candidates ready for ingestion ===");
        for (i, c) in discovered.iter().enumerate() {
            println!("CANDIDATE {}|domain={}|confidence={:.2}|source={}|{}",
                i + 1, c.domain, c.confidence, c.source, c.relation);
        }
    }
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
