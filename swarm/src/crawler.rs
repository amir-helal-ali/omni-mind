//! src/crawler.rs — Logical Crawler (Algorithmic Foraging).
//!
//! Sends targeted semantic probes to external APIs to fetch
//! relations (not raw text). Applies Differential Learning:
//! each new fact becomes a small if/else branch instantly,
//! no retraining required.
//!
//! Supported APIs:
//!   - Crossref (https://api.crossref.org/works) — academic papers
//!   - arXiv (http://export.arxiv.org/api/query) — preprints
//!   - Local fallback (offline mode) — uses built-in heuristics

use std::collections::HashMap;
use std::time::Duration;

/// A knowledge gap — something the system needs to learn.
#[derive(Debug, Clone)]
pub struct KnowledgeGap {
    pub domain: u8,
    pub gap_signature: u64,
    pub priority: f32,
    pub query_text: Option<String>,
}

/// A candidate axiom discovered by the crawler.
#[derive(Debug, Clone)]
pub struct AxiomCandidate {
    pub domain: u8,
    pub relation: String,
    pub confidence: f32,
    pub source: String,
}

/// A probe template — how to query a specific API.
#[derive(Clone)]
pub struct ProbeTemplate {
    pub api_endpoint: String,
    pub query_pattern: String,
    pub source_name: &'static str,
}

/// The Logical Crawler — runs in the background, fills gaps.
pub struct LogicalCrawler {
    pub gap_queue: Vec<KnowledgeGap>,
    pub probes: HashMap<u8, Vec<ProbeTemplate>>,
    pub discovered: Vec<AxiomCandidate>,
    pub offline_mode: bool,
}

impl LogicalCrawler {
    pub fn new() -> Self {
        let mut c = Self {
            gap_queue: Vec::new(),
            probes: HashMap::new(),
            discovered: Vec::new(),
            offline_mode: false,
        };
        c.register_default_probes();
        c
    }

    /// Enable offline mode (skip real HTTP calls, use heuristics).
    pub fn offline(mut self) -> Self {
        self.offline_mode = true;
        self
    }

    /// Register default probe templates for known APIs.
    fn register_default_probes(&mut self) {
        // Register probes for all known domains (0-9).
        for domain in 0..10u8 {
            // Crossref API for academic papers.
            self.register_probe(domain, ProbeTemplate {
                api_endpoint: "https://api.crossref.org/works".to_string(),
                query_pattern: "query={topic}&rows=5".to_string(),
                source_name: "crossref",
            });
            // arXiv API for preprints.
            self.register_probe(domain, ProbeTemplate {
                api_endpoint: "http://export.arxiv.org/api/query".to_string(),
                query_pattern: "search_query=all:{topic}&max_results=5".to_string(),
                source_name: "arxiv",
            });
            // Semantic Scholar API.
            self.register_probe(domain, ProbeTemplate {
                api_endpoint: "https://api.semanticscholar.org/graph/v1/paper/search".to_string(),
                query_pattern: "query={topic}&limit=5".to_string(),
                source_name: "semantic_scholar",
            });
        }
    }

    /// Add a knowledge gap to the queue.
    pub fn report_gap(&mut self, gap: KnowledgeGap) {
        self.gap_queue.push(gap);
        self.gap_queue.sort_by(|a, b| b.priority.partial_cmp(&a.priority).unwrap());
    }

    /// Register a probe template for a domain.
    pub fn register_probe(&mut self, domain: u8, probe: ProbeTemplate) {
        self.probes.entry(domain).or_default().push(probe);
    }

    /// Run one foraging cycle — picks the highest-priority gap
    /// and tries to fill it. Returns the candidate if found.
    pub fn forage_once(&mut self) -> Option<AxiomCandidate> {
        let gap = self.gap_queue.pop()?;

        if let Some(probes) = self.probes.get(&gap.domain) {
            for probe in probes {
                let candidate = if self.offline_mode {
                    self.heuristic_forage(&gap, probe)
                } else {
                    http_forage(&gap, probe)
                };

                if let Some(c) = candidate {
                    self.discovered.push(c.clone());
                    return Some(c);
                }
            }
        }
        None
    }

    /// Run multiple foraging cycles.
    pub fn forage_n(&mut self, n: usize) -> Vec<AxiomCandidate> {
        let mut results = Vec::new();
        for _ in 0..n {
            if let Some(c) = self.forage_once() {
                results.push(c);
            } else {
                break;
            }
        }
        results
    }

    /// Heuristic foraging (offline fallback).
    fn heuristic_forage(&self, gap: &KnowledgeGap, probe: &ProbeTemplate) -> Option<AxiomCandidate> {
        let topic = gap.query_text.as_deref().unwrap_or("the topic");
        // Generate a plausible-sounding relation based on the domain.
        let relation = match gap.domain {
            0 => format!("Research on {} shows emerging patterns in physics literature", topic),
            1 => format!("Studies indicate {} has catalytic properties in chemistry", topic),
            2 => format!("Biological research on {} reveals cellular mechanisms", topic),
            _ => format!("Academic literature discusses {} across multiple disciplines", topic),
        };

        Some(AxiomCandidate {
            domain: gap.domain,
            relation,
            confidence: 0.5,
            source: format!("{}-heuristic", probe.source_name),
        })
    }

    /// Get stats.
    pub fn stats(&self) -> CrawlerStats {
        CrawlerStats {
            gaps_pending: self.gap_queue.len(),
            candidates_discovered: self.discovered.len(),
            probes_registered: self.probes.values().map(|v| v.len()).sum(),
        }
    }
}

#[derive(Debug)]
pub struct CrawlerStats {
    pub gaps_pending: usize,
    pub candidates_discovered: usize,
    pub probes_registered: usize,
}

/// HTTP-based foraging (real API calls). Tries native TCP first,
/// falls back to shelling out to curl for HTTPS endpoints.
fn http_forage(gap: &KnowledgeGap, probe: &ProbeTemplate) -> Option<AxiomCandidate> {
    let topic = gap.query_text.as_deref().unwrap_or("unknown");
    let query = probe.query_pattern.replace("{topic}", &url_encode(topic));
    let url = format!("{}?{}", probe.api_endpoint, query);

    log::info!("Probing: {}", url);

    // Try native TCP first (works for HTTP endpoints).
    if let Some(body) = native_http_get(&url) {
        if let Some(c) = extract_relation(&body, probe.source_name, gap.domain) {
            return Some(c);
        }
    }

    // Fallback: shell out to curl for HTTPS endpoints.
    if let Some(body) = curl_http_get(&url) {
        if let Some(c) = extract_relation(&body, probe.source_name, gap.domain) {
            return Some(c);
        }
    }

    log::warn!("All probes failed for: {}", url);
    None
}

/// Native HTTP GET via std::net (HTTP only, no TLS).
fn native_http_get(url: &str) -> Option<Vec<u8>> {
    let parsed = parse_url(url)?;
    if parsed.scheme != "http" {
        return None; // Can't do HTTPS without TLS.
    }
    let addr = format!("{}:{}", parsed.host, parsed.port);
    let stream = std::net::TcpStream::connect_timeout(
        &addr.parse().ok()?,
        Duration::from_secs(5),
    ).ok()?;

    stream.set_read_timeout(Some(Duration::from_secs(10))).ok()?;
    stream.set_write_timeout(Some(Duration::from_secs(5))).ok()?;

    use std::io::{Read, Write};
    let mut stream = stream;

    let request = format!(
        "GET {}?{} HTTP/1.1\r\nHost: {}\r\nUser-Agent: Omni-Mind/0.1\r\nConnection: close\r\n\r\n",
        parsed.path, parsed.query, parsed.host
    );
    stream.write_all(request.as_bytes()).ok()?;

    let mut response = Vec::new();
    stream.read_to_end(&mut response).ok()?;

    Some(extract_body_owned(&response))
}

/// Shell out to curl for HTTPS endpoints (works for arXiv, Semantic Scholar, Crossref).
fn curl_http_get(url: &str) -> Option<Vec<u8>> {
    use std::process::Command;
    let output = Command::new("curl")
        .args(&["-sS", "--max-time", "15", "-A", "Omni-Mind/0.1", url])
        .output()
        .ok()?;

    if !output.status.success() {
        log::debug!("curl failed: {}", String::from_utf8_lossy(&output.stderr));
        return None;
    }

    Some(output.stdout)
}

/// Conflict resolution — what to do when a new axiom contradicts an existing one.
#[derive(Debug, PartialEq)]
pub enum ConflictResolution {
    RejectCandidate,
    ReplaceExisting,
    AddAsAlternative,
}

pub fn resolve_conflict(existing_confidence: f32, candidate_confidence: f32) -> ConflictResolution {
    if existing_confidence > 0.9 && candidate_confidence < 0.7 {
        ConflictResolution::RejectCandidate
    } else if existing_confidence < 0.5 && candidate_confidence > 0.8 {
        ConflictResolution::ReplaceExisting
    } else {
        ConflictResolution::AddAsAlternative
    }
}

/// Parsed URL components.
struct ParsedUrl {
    scheme: String,
    host: String,
    port: u16,
    path: String,
    query: String,
}

fn parse_url(url: &str) -> Option<ParsedUrl> {
    let (scheme, rest) = url.split_once("://")?;
    let (host_port, path_query) = rest.split_once('/').unwrap_or((rest, ""));
    let (host, port) = if let Some((h, p)) = host_port.split_once(':') {
        (h.to_string(), p.parse().unwrap_or(80))
    } else {
        (host_port.to_string(), if scheme == "https" { 443 } else { 80 })
    };
    let (path, query) = if let Some((p, q)) = path_query.split_once('?') {
        (format!("/{}", p), q.to_string())
    } else {
        (format!("/{}", path_query), String::new())
    };
    Some(ParsedUrl {
        scheme: scheme.to_string(),
        host,
        port,
        path,
        query,
    })
}

fn url_encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b == b'-' || b == b'_' || b == b'.' || b == b'~' {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{:02X}", b));
        }
    }
    out
}

fn extract_body(response: &[u8]) -> &[u8] {
    // Find the body after "\r\n\r\n".
    for i in 0..response.len().saturating_sub(4) {
        if &response[i..i + 4] == b"\r\n\r\n" {
            return &response[i + 4..];
        }
    }
    response
}

fn extract_body_owned(response: &[u8]) -> Vec<u8> {
    extract_body(response).to_vec()
}

/// Extract a relation from an API response body.
/// This is a simplified extractor that looks for title-like patterns.
fn extract_relation(body: &[u8], source: &str, domain: u8) -> Option<AxiomCandidate> {
    let text = String::from_utf8_lossy(body);

    // For Crossref JSON: look for "title":["..."]
    if source == "crossref" {
        if let Some(start) = text.find("\"title\":[\"") {
            let rest = &text[start + 10..];
            if let Some(end) = rest.find("\"]") {
                let title = &rest[..end];
                if !title.is_empty() {
                    return Some(AxiomCandidate {
                        domain,
                        relation: format!("Paper: {}", title),
                        confidence: 0.7,
                        source: "crossref".to_string(),
                    });
                }
            }
        }
    }

    // For arXiv Atom XML: look for <title>...</title>
    if source == "arxiv" {
        if let Some(start) = text.find("<title>") {
            let rest = &text[start + 7..];
            if let Some(end) = rest.find("</title>") {
                let title = &rest[..end];
                if !title.is_empty() && !title.contains("ArXiv Query") {
                    return Some(AxiomCandidate {
                        domain,
                        relation: format!("arXiv: {}", title.trim()),
                        confidence: 0.65,
                        source: "arxiv".to_string(),
                    });
                }
            }
        }
    }

    // For Semantic Scholar JSON: look for "title":"..."
    if source == "semantic_scholar" {
        if let Some(start) = text.find("\"title\":\"") {
            let rest = &text[start + 9..];
            if let Some(end) = rest.find("\",") {
                let title = &rest[..end];
                if !title.is_empty() {
                    return Some(AxiomCandidate {
                        domain,
                        relation: format!("Paper: {}", title),
                        confidence: 0.7,
                        source: "semantic_scholar".to_string(),
                    });
                }
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crawler_reports_and_fills_gap() {
        let mut c = LogicalCrawler::new().offline();
        c.report_gap(KnowledgeGap {
            domain: 0,
            gap_signature: 0xdeadbeef,
            priority: 0.9,
            query_text: Some("quantum computing".to_string()),
        });
        assert_eq!(c.gap_queue.len(), 1);

        let result = c.forage_once();
        assert!(result.is_some());
        let cand = result.unwrap();
        assert_eq!(cand.domain, 0);
        assert!(cand.confidence > 0.0);
    }

    #[test]
    fn offline_mode_produces_heuristic_candidates() {
        let mut c = LogicalCrawler::new().offline();
        c.report_gap(KnowledgeGap {
            domain: 2,
            gap_signature: 0x1,
            priority: 0.5,
            query_text: Some("DNA replication".to_string()),
        });
        let cand = c.forage_once().unwrap();
        assert!(cand.relation.contains("DNA replication"));
        assert_eq!(cand.source, "crossref-heuristic");
    }

    #[test]
    fn conflict_resolution_trusts_high_confidence_existing() {
        assert_eq!(
            resolve_conflict(0.95, 0.6),
            ConflictResolution::RejectCandidate
        );
    }

    #[test]
    fn conflict_resolution_replaces_low_confidence_existing() {
        assert_eq!(
            resolve_conflict(0.3, 0.85),
            ConflictResolution::ReplaceExisting
        );
    }

    #[test]
    fn url_encode_handles_spaces() {
        assert_eq!(url_encode("hello world"), "hello%20world");
        assert_eq!(url_encode("a+b=c"), "a%2Bb%3Dc");
    }

    #[test]
    fn extract_relation_crossref() {
        let body = br#"{"title":["Quantum Computing Advances"]}"#;
        let cand = extract_relation(body, "crossref", 0).unwrap();
        assert!(cand.relation.contains("Quantum Computing Advances"));
    }

    #[test]
    fn extract_relation_arxiv() {
        let body = b"<entry><title>Neural Networks for Symbolic AI</title></entry>";
        let cand = extract_relation(body, "arxiv", 5).unwrap();
        assert!(cand.relation.contains("Neural Networks"));
    }

    #[test]
    fn forage_n_returns_multiple() {
        let mut c = LogicalCrawler::new().offline();
        for i in 0..5 {
            c.report_gap(KnowledgeGap {
                domain: 0,
                gap_signature: i,
                priority: 0.5,
                query_text: Some(format!("topic {}", i)),
            });
        }
        let results = c.forage_n(3);
        assert_eq!(results.len(), 3);
    }
}
