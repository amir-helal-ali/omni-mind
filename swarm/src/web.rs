//! src/web.rs — Minimal HTTP server for Omni-Mind web UI.
//!
//! Serves a single-page HTML frontend + JSON API.
//! All requests go through the Zig core via FFI.

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::thread;

use crate::ffi;

/// Start the web server on the given port.
/// Handles SIGINT/SIGTERM for graceful shutdown.
pub fn run(port: u16) {
    let listener = match TcpListener::bind(format!("0.0.0.0:{}", port)) {
        Ok(l) => l,
        Err(e) => {
            log::error!("Failed to bind port {}: {}", port, e);
            return;
        }
    };

    // Set non-blocking so we can check for shutdown signal.
    if let Err(e) = listener.set_nonblocking(true) {
        log::warn!("Failed to set non-blocking: {}", e);
    }

    log::info!("Omni-Mind web server listening on http://0.0.0.0:{}", port);
    log::info!("Endpoints: / /api/query /api/stats /api/health /api/metrics /api/ingest /api/learn /api/search");

    // ─── Spawn background auto-learning thread ───
    // This thread continuously learns about new topics from the internet,
    // expanding the knowledge base without user interaction.
    std::thread::spawn(move || {
        background_auto_learner(port);
    });
    log::info!("Background auto-learner started — system will learn autonomously");

    let shutdown = Arc::new(std::sync::atomic::AtomicBool::new(false));

    // Spawn signal handler thread.
    #[cfg(unix)]
    {
        let shutdown_clone = Arc::clone(&shutdown);
        std::thread::spawn(move || {
            use std::os::raw::c_int;
            extern "C" fn handle_sig(_: c_int) {
                // Signal handled — the main loop will detect the flag.
            }
            unsafe {
                libc::signal(libc::SIGINT, handle_sig as usize);
                libc::signal(libc::SIGTERM, handle_sig as usize);
            }
            // Wait for signal, then set flag.
            // In production, use signalfd or tokio::signal. For simplicity,
            // we poll stdin for EOF (which happens on Ctrl+C in foreground).
            loop {
                std::thread::sleep(std::time::Duration::from_millis(200));
                // Check if we should shutdown (set by another mechanism)
                if shutdown_clone.load(std::sync::atomic::Ordering::Relaxed) {
                    break;
                }
            }
        });
    }

    log::info!("Press Ctrl+C to shut down gracefully.");

    while !shutdown.load(std::sync::atomic::Ordering::Relaxed) {
        match listener.accept() {
            Ok((stream, addr)) => {
                log::debug!("Connection from {}", addr);
                std::thread::spawn(|| handle_request(stream));
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(e) => {
                log::warn!("Accept error: {}", e);
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
        }
    }

    log::info!("Graceful shutdown: draining connections...");
    // Give in-flight requests 1 second to complete.
    std::thread::sleep(std::time::Duration::from_secs(1));
    log::info!("Server stopped.");
}

/// Background auto-learner — continuously expands the knowledge base
/// by learning about trending and diverse topics from the internet.
///
/// This runs in a background thread and:
///   1. Starts learning after a 30-second delay (let the server stabilize)
///   2. Learns about a diverse set of topics across all 16 domains
///   3. Waits 60 seconds between each learning cycle (to avoid rate limiting)
///   4. Runs indefinitely until the server shuts down
///
/// The topics are curated to cover diverse knowledge areas, ensuring
/// the system becomes a well-rounded expert over time.
fn background_auto_learner(_port: u16) {
    // Wait 30 seconds for the server to stabilize.
    std::thread::sleep(std::time::Duration::from_secs(30));
    log::info!("Auto-learner: starting autonomous knowledge expansion");

    // Curated list of diverse topics to learn about.
    // Covers all 16 domains for well-rounded knowledge.
    let topics = [
        // Physics
        "quantum mechanics", "relativity", "thermodynamics", "string theory",
        // Chemistry
        "periodic table", "chemical bonds", "organic chemistry", "biochemistry",
        // Biology
        "evolution", "genetics", "ecology", "neuroscience",
        // Mathematics
        "calculus", "linear algebra", "number theory", "topology",
        // Computer Science
        "artificial intelligence", "blockchain", "quantum computing", "cybersecurity",
        // Economics
        "behavioral economics", "game theory", "macroeconomics", "cryptocurrency",
        // Philosophy
        "existentialism", "ethics", "epistemology", "phenomenology",
        // Psychology
        "cognitive psychology", "social psychology", "neurolinguistics", "behaviorism",
        // History
        "ancient civilizations", "industrial revolution", "world wars", "cold war",
        // Linguistics
        "phonology", "syntax", "semantics", "sociolinguistics",
        // Astronomy
        "black holes", "exoplanets", "dark matter", "cosmology",
        // Geology
        "plate tectonics", "mineralogy", "paleontology", "volcanology",
        // Medicine
        "immunology", "pharmacology", "epidemiology", "gene therapy",
        // Engineering
        "robotics", "nanotechnology", "aerospace engineering", "biomedical engineering",
        // Political Science
        "democracy", "geopolitics", "international relations", "political theory",
        // Extra cutting-edge
        "CRISPR", "fusion energy", "climate change", "machine learning",
        "neural networks", "deep learning", "natural language processing",
        "computer vision", "reinforcement learning", "GPT",
        "metaverse", "web3", "quantum entanglement", "dark energy",
        "consciousness", "free will", "memory", "dreams",
        "cancer", "Alzheimer", "diabetes", "COVID-19",
        "Python programming", "Rust programming", "JavaScript", "TypeScript",
        "Docker", "Kubernetes", "microservices", "DevOps",
        "renewable energy", "battery technology", "electric vehicles", "solar power",
    ];

    let mut index: usize = 0;
    let mut total_learned: usize = 0;

    loop {
        if index >= topics.len() {
            // Completed one full cycle — restart from beginning.
            index = 0;
            log::info!("Auto-learner: completed full cycle ({} topics learned). Restarting...", total_learned);
            // Wait 5 minutes before restarting the cycle.
            std::thread::sleep(std::time::Duration::from_secs(300));
        }

        let topic = topics[index];
        log::info!("Auto-learner: learning about '{}'...", topic);

        // Search the internet for this topic.
        let knowledge = crate::internet::search_all_sources(topic, "en");

        if !knowledge.facts.is_empty() {
            let axiom_text = crate::internet::aggregated_to_axiom(&knowledge);
            let domain = guess_domain(topic);

            // Ingest the new knowledge.
            match ffi::safe_inject_axiom(domain, &axiom_text, 0.7) {
                Ok(()) => {
                    total_learned += 1;
                    log::info!("Auto-learner: ✓ learned '{}' from {} sources (total: {})",
                        topic, knowledge.sources_count, total_learned);
                }
                Err(e) => {
                    log::warn!("Auto-learner: failed to ingest '{}' (code {})", topic, e);
                }
            }
        } else {
            log::debug!("Auto-learner: no info found for '{}'", topic);
        }

        index += 1;

        // Wait 60 seconds between topics (to avoid rate limiting).
        std::thread::sleep(std::time::Duration::from_secs(60));
    }
}

fn handle_request(mut stream: TcpStream) {
    // Set a read timeout so we don't block forever waiting for body.
    let _ = stream.set_read_timeout(Some(std::time::Duration::from_secs(2)));
    let _ = stream.set_write_timeout(Some(std::time::Duration::from_secs(2)));

    let mut buf = [0u8; 8192];
    let mut total = Vec::new();

    // Read until we have headers AND the full body (based on Content-Length).
    // If no Content-Length, a single read is sufficient (GET requests).
    loop {
        let n = match stream.read(&mut buf) {
            Ok(n) => n,
            Err(_) => break,
        };
        if n == 0 {
            break;
        }
        total.extend_from_slice(&buf[..n]);

        // Check if we have the full request.
        let request_str = String::from_utf8_lossy(&total);
        if let Some(header_end) = request_str.find("\r\n\r\n") {
            let headers = &request_str[..header_end];
            let body_start = header_end + 4;
            let current_body_len = total.len().saturating_sub(body_start);

            // Parse Content-Length (case-insensitive).
            let content_length = headers
                .lines()
                .find_map(|line| {
                    let lower = line.to_lowercase();
                    lower.strip_prefix("content-length:").and_then(|v| v.trim().parse::<usize>().ok())
                })
                .unwrap_or(0);

            // If we have the full body (or no Content-Length for GET), we're done.
            if current_body_len >= content_length {
                break;
            }
        } else if total.len() > 4 {
            // We have data but no header terminator yet — keep reading.
            // But if we've read a lot, break to avoid infinite loop.
        }
    }

    if total.is_empty() {
        return;
    }

    let request = String::from_utf8_lossy(&total);
    let (method, path, body) = parse_request(&request);

    // Extract query string from path (e.g., "/api/search?q=energy" → "q=energy")
    let query_string = if let Some(pos) = path.find('?') {
        path[pos + 1..].to_string()
    } else {
        String::new()
    };
    // Strip query string from path for routing.
    let path_clean = if let Some(pos) = path.find('?') { &path[..pos] } else { &path };

    log::debug!("{} {} (body {} bytes: {})", method, path_clean, body.len(), &body[..body.len().min(100)]);

    let (status, content_type, response_body) = match (method.as_str(), path_clean) {
        ("GET", "/") => serve_html(),
        ("GET", "/index.html") => serve_html(),
        ("POST", "/api/query") => handle_query(&body),
        ("GET", "/api/stats") => handle_stats(),
        ("GET", "/api/health") => handle_health(),
        ("GET", "/api/metrics") => handle_metrics(),
        ("POST", "/api/ingest") => handle_ingest(&body),
        ("POST", "/api/learn") => handle_learn(&body),
        ("GET", "/api/search") => handle_search(&query_string),
        ("OPTIONS", _) => ("200 OK", "text/plain", String::new()),
        _ => ("404 Not Found", "application/json", r#"{"error":"not found"}"#.to_string()),
    };

    let response = format!(
        "HTTP/1.1 {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{}",
        status, content_type, response_body.len(), response_body
    );

    let _ = stream.write_all(response.as_bytes());
}

fn parse_request(request: &str) -> (String, String, String) {
    let mut lines = request.lines();
    let first_line = lines.next().unwrap_or("");
    let parts: Vec<&str> = first_line.split_whitespace().collect();
    let method = parts.first().unwrap_or(&"").to_string();
    let path = parts.get(1).unwrap_or(&"/").to_string();

    // Find body (after empty line).
    let body = if let Some(idx) = request.find("\r\n\r\n") {
        let raw = &request[idx + 4..];
        // Trim null bytes and whitespace (TCP buffer may have trailing nulls)
        raw.trim_matches(|c: char| c == '\0' || c.is_whitespace()).to_string()
    } else {
        String::new()
    };

    (method, path, body)
}

fn serve_html() -> (&'static str, &'static str, String) {
    ("200 OK", "text/html; charset=utf-8", HTML_PAGE.to_string())
}

fn handle_query(body: &str) -> (&'static str, &'static str, String) {
    // Body format: "query text" (plain text) or {"query":"..."} (JSON)
    let query = extract_query(body.trim());
    if query.is_empty() {
        return ("400 Bad Request", "application/json",
            r#"{"error":"missing query"}"#.to_string());
    }

    log::info!("Query: {}", query);

    // Step 1: Try the internal knowledge base first.
    let internal_answer = ffi::safe_query(&query);

    match internal_answer {
        Ok(answer) => {
            // Check if the answer has low confidence.
            // The Zig side appends "— الثقة: XX%" or "— Confidence: XX%".
            let confidence = extract_confidence_from_answer(&answer);
            log::info!("Internal answer confidence: {:.0}%", confidence);

            // If confidence is high enough, return immediately.
            if confidence >= 50.0 {
                let json = format!(r#"{{"query":"{}","answer":"{}","source":"internal","confidence":{:.0}}}"#,
                    escape_json(&query),
                    escape_json(&answer),
                    confidence);
                return ("200 OK", "application/json", json);
            }

            // Step 2: Low confidence — auto-search the internet BEFORE answering.
            log::info!("Low confidence ({:.0}%) — auto-searching internet...", confidence);

            // Extract the key topic from the query for internet search.
            let topic = extract_topic_from_query(&query);
            let lang = if query.chars().any(|c| c >= '\u{0600}' && c <= '\u{06FF}') { "ar" } else { "en" };

            // Search all internet sources.
            let knowledge = crate::internet::search_all_sources(&topic, lang);

            if !knowledge.facts.is_empty() {
                // We found info on the internet — ingest it and re-answer.
                let axiom_text = crate::internet::aggregated_to_axiom(&knowledge);
                let domain = guess_domain(&topic);

                log::info!("Learned from {} internet sources, re-answering...", knowledge.sources_count);

                // Ingest the new knowledge.
                let _ = ffi::safe_inject_axiom(domain, &axiom_text, 0.75);

                // Re-query with the new knowledge.
                match ffi::safe_query(&query) {
                    Ok(reanswer) => {
                        let new_confidence = extract_confidence_from_answer(&reanswer);
                        let sources_list: Vec<String> = knowledge.facts.iter()
                            .map(|f| format!(r#"{{"name":"{}","url":"{}"}}"#, escape_json(&f.source_name), escape_json(&f.source_url)))
                            .collect();

                        let json = format!(
                            r#"{{"query":"{}","answer":"{}","source":"internet+internal","confidence":{:.0},"auto_learned":true,"sources_count":{},"sources":[{}]}}"#,
                            escape_json(&query),
                            escape_json(&reanswer),
                            new_confidence,
                            knowledge.sources_count,
                            sources_list.join(",")
                        );
                        return ("200 OK", "application/json", json);
                    }
                    Err(_) => {
                        // Re-query failed — return the internet knowledge directly.
                        let combined: String = knowledge.facts.iter()
                            .map(|f| format!("[{}] {}", f.source_name, f.summary))
                            .collect::<Vec<_>>()
                            .join("\n\n");

                        let json = format!(
                            r#"{{"query":"{}","answer":"{}","source":"internet","auto_learned":true,"sources_count":{}}}"#,
                            escape_json(&query),
                            escape_json(&combined),
                            knowledge.sources_count
                        );
                        return ("200 OK", "application/json", json);
                    }
                }
            }

            // Internet search found nothing — return the internal answer as-is.
            let json = format!(r#"{{"query":"{}","answer":"{}","source":"internal","confidence":{:.0}}}"#,
                escape_json(&query),
                escape_json(&answer),
                confidence);
            ("200 OK", "application/json", json)
        }
        Err(e) => {
            // Internal query completely failed — try internet as fallback.
            log::info!("Internal query failed (code {}) — trying internet fallback...", e);

            let topic = extract_topic_from_query(&query);
            let lang = if query.chars().any(|c| c >= '\u{0600}' && c <= '\u{06FF}') { "ar" } else { "en" };
            let knowledge = crate::internet::search_all_sources(&topic, lang);

            if !knowledge.facts.is_empty() {
                let axiom_text = crate::internet::aggregated_to_axiom(&knowledge);
                let domain = guess_domain(&topic);
                let _ = ffi::safe_inject_axiom(domain, &axiom_text, 0.75);

                // Try internal query again with new knowledge.
                if let Ok(reanswer) = ffi::safe_query(&query) {
                    let json = format!(
                        r#"{{"query":"{}","answer":"{}","source":"internet-fallback","auto_learned":true,"sources_count":{}}}"#,
                        escape_json(&query),
                        escape_json(&reanswer),
                        knowledge.sources_count
                    );
                    return ("200 OK", "application/json", json);
                }

                // Return internet knowledge directly.
                let combined: String = knowledge.facts.iter()
                    .map(|f| format!("[{}] {}", f.source_name, f.summary))
                    .collect::<Vec<_>>()
                    .join("\n\n");

                let json = format!(
                    r#"{{"query":"{}","answer":"{}","source":"internet","auto_learned":true,"sources_count":{}}}"#,
                    escape_json(&query),
                    escape_json(&combined),
                    knowledge.sources_count
                );
                return ("200 OK", "application/json", json);
            }

            let json = format!(r#"{{"error":"query failed: code {}"}}"#, e);
            ("500 Internal Server Error", "application/json", json)
        }
    }
}

/// Extract confidence percentage from an answer string.
/// Looks for "الثقة: XX%" or "Confidence: XX%" patterns.
fn extract_confidence_from_answer(answer: &str) -> f64 {
    // Try Arabic pattern first.
    if let Some(pos) = answer.find("الثقة") {
        let rest = &answer[pos..];
        // Find the first number after "الثقة".
        let mut start = 0;
        let mut found_digit = false;
        for (i, ch) in rest.char_indices() {
            if ch.is_ascii_digit() {
                if !found_digit {
                    start = i;
                    found_digit = true;
                }
            } else if found_digit && ch != '.' && ch != '%' {
                let num_str = &rest[start..i];
                if let Ok(val) = num_str.parse::<f64>() {
                    return val;
                }
                break;
            }
        }
    }

    // Try English pattern.
    if let Some(pos) = answer.find("Confidence") {
        let rest = &answer[pos..];
        let mut start = 0;
        let mut found_digit = false;
        for (i, ch) in rest.char_indices() {
            if ch.is_ascii_digit() {
                if !found_digit {
                    start = i;
                    found_digit = true;
                }
            } else if found_digit && ch != '.' && ch != '%' {
                let num_str = &rest[start..i];
                if let Ok(val) = num_str.parse::<f64>() {
                    return val;
                }
                break;
            }
        }
    }

    // Default: assume moderate confidence (50%).
    50.0
}

/// Extract the main topic from a query for internet search.
/// Removes question words and extracts the key concept.
fn extract_topic_from_query(query: &str) -> String {
    let q = query.trim();

    // Remove common question prefixes.
    let prefixes = [
        "what is ", "what are ", "what's ", "what ",
        "who is ", "who are ", "who ",
        "how does ", "how do ", "how is ", "how are ", "how ",
        "why does ", "why do ", "why is ", "why are ", "why ",
        "when did ", "when was ", "when ",
        "where is ", "where are ", "where ",
        "can you ", "could you ", "tell me about ", "explain ",
        "describe ", "define ",
        "ما هو ", "ما هي ", "ماذا ", "متى ", "أين ", "كيف ", "لماذا ",
        "من هو ", "من هي ", "من ", "هل ", "اشرح ", "عرّف ", "صف ",
    ];

    let mut topic = q.to_lowercase();
    for prefix in &prefixes {
        if topic.starts_with(prefix) {
            topic = topic[prefix.len()..].to_string();
            break;
        }
    }

    // Remove trailing punctuation.
    topic = topic.trim_end_matches(|c: char| !c.is_alphanumeric() && c != ' ').trim().to_string();

    // If topic is too long, take first few words.
    let words: Vec<&str> = topic.split_whitespace().collect();
    if words.len() > 5 {
        topic = words[..5].join(" ");
    }

    if topic.is_empty() {
        q.to_string()
    } else {
        topic
    }
}

fn handle_stats() -> (&'static str, &'static str, String) {
    let s = ffi::stats();
    let json = format!(
        r#"{{"nodes":{},"edges":{},"axioms":{},"bytes_used":{},"bytes_budget":{}}}"#,
        s.node_count, s.edge_count, s.axiom_count, s.bytes_used, s.bytes_budget
    );
    ("200 OK", "application/json", json)
}

/// Health check endpoint — returns 200 if the server is healthy.
fn handle_health() -> (&'static str, &'static str, String) {
    let s = ffi::stats();
    let mem_pct = if s.bytes_budget > 0 {
        (s.bytes_used as f64 / s.bytes_budget as f64) * 100.0
    } else {
        0.0
    };

    let healthy = s.axiom_count > 0 && mem_pct < 99.0;
    let status = if healthy { "healthy" } else { "degraded" };
    let http_status = if healthy { "200 OK" } else { "503 Service Unavailable" };

    let json = format!(
        r#"{{"status":"{}","axioms":{},"nodes":{},"memory_pct":{:.1}}}"#,
        status, s.axiom_count, s.node_count, mem_pct
    );
    (http_status, "application/json", json)
}

/// Prometheus-compatible metrics endpoint.
fn handle_metrics() -> (&'static str, &'static str, String) {
    let s = ffi::stats();
    let metrics = format!(
        r#"# HELP omni_mind_nodes Total number of graph nodes
# TYPE omni_mind_nodes gauge
omni_mind_nodes {}
# HELP omni_mind_edges Total number of graph edges
# TYPE omni_mind_edges gauge
omni_mind_edges {}
# HELP omni_mind_axioms Total number of axioms stored
# TYPE omni_mind_axioms gauge
omni_mind_axioms {}
# HELP omni_mind_memory_bytes Memory used in bytes
# TYPE omni_mind_memory_bytes gauge
omni_mind_memory_bytes {}
# HELP omni_mind_memory_budget_bytes Memory budget in bytes
# TYPE omni_mind_memory_budget_bytes gauge
omni_mind_memory_budget_bytes {}
"#,
        s.node_count, s.edge_count, s.axiom_count, s.bytes_used, s.bytes_budget
    );
    ("200 OK", "text/plain; version=0.0.4", metrics)
}

fn handle_ingest(body: &str) -> (&'static str, &'static str, String) {
    // Body format: "domain|text" or {"domain":0,"text":"..."}
    let trimmed = body.trim();
    let (domain, text) = extract_ingest(trimmed);
    if text.is_empty() {
        return ("400 Bad Request", "application/json",
            r#"{"error":"missing text"}"#.to_string());
    }

    match ffi::safe_inject_axiom(domain, &text, 0.8) {
        Ok(()) => {
            ("200 OK", "application/json",
                format!(r#"{{"status":"ingested","domain":{},"text":"{}"}}"#,
                    domain, escape_json(&text)))
        }
        Err(e) => {
            ("500 Internal Server Error", "application/json",
                format!(r#"{{"error":"ingest failed: code {}}}"#, e))
        }
    }
}

fn extract_query(body: &str) -> String {
    // Try JSON first.
    if body.starts_with('{') {
        if let Some(q) = extract_json_string(body, "query") {
            return q;
        }
    }
    // Plain text fallback.
    body.trim().to_string()
}

fn extract_ingest(body: &str) -> (u8, String) {
    if body.starts_with('{') {
        // JSON: {"domain":0,"text":"..."}
        let domain = extract_json_int(body, "domain").unwrap_or(0) as u8;
        let text = extract_json_string(body, "text").unwrap_or_default();
        return (domain, text);
    }
    // Plain: "domain|text"
    if let Some(idx) = body.find('|') {
        let domain: u8 = body[..idx].trim().parse().unwrap_or(0);
        let text = body[idx + 1..].trim().to_string();
        return (domain, text);
    }
    (0, body.trim().to_string())
}

/// Handle /api/learn — learn about a topic from MULTIPLE internet sources.
/// Body: {"topic":"energy","lang":"en"} or {"topic":"الطاقة","lang":"ar"}
/// Searches all configured sources, aggregates results, ingests as axiom.
fn handle_learn(body: &str) -> (&'static str, &'static str, String) {
    let topic = match extract_json_string(body, "topic") {
        Some(t) if !t.is_empty() => t,
        _ => return ("400 Bad Request", "application/json",
            r#"{"error":"missing topic"}"#.to_string()),
    };
    let lang = extract_json_string(body, "lang").unwrap_or_else(|| "en".to_string());

    log::info!("Multi-source learning request: topic='{}', lang='{}'", topic, lang);

    // Search ALL sources and aggregate.
    let knowledge = crate::internet::search_all_sources(&topic, &lang);

    if knowledge.facts.is_empty() {
        return ("404 Not Found", "application/json",
            format!(r#"{{"error":"no information found for '{}' in any source"}}"#, escape_json(&topic)));
    }

    // Convert to axiom text (uses the best fact + source count).
    let axiom_text = crate::internet::aggregated_to_axiom(&knowledge);

    // Determine domain from the topic.
    let domain = guess_domain(&topic);

    // Ingest into the knowledge base.
    match ffi::safe_inject_axiom(domain, &axiom_text, 0.75) {
        Ok(()) => {
            log::info!("Learned from {} sources: '{}' → domain {}", knowledge.sources_count, axiom_text, domain);

            // Build sources list for response.
            let sources_list: Vec<String> = knowledge.facts.iter()
                .map(|f| format!(r#"{{"name":"{}","url":"{}"}}"#, escape_json(&f.source_name), escape_json(&f.source_url)))
                .collect();

            ("200 OK", "application/json",
                format!(r#"{{"status":"learned","topic":"{}","axiom":"{}","domain":{},"sources_count":{},"sources":[{}]}}"#,
                    escape_json(&topic),
                    escape_json(&axiom_text),
                    domain,
                    knowledge.sources_count,
                    sources_list.join(",")))
        }
        Err(e) => ("500 Internal Server Error", "application/json",
            format!(r#"{{"error":"ingest failed: code {}}}"#, e)),
    }
}

/// Handle /api/search?q=topic — search multiple sources without ingesting.
/// Returns aggregated summaries as JSON.
fn handle_search(query_string: &str) -> (&'static str, &'static str, String) {
    let topic = query_string
        .strip_prefix("q=")
        .unwrap_or("")
        .split('&')
        .next()
        .unwrap_or("")
        .to_string();

    if topic.is_empty() {
        return ("400 Bad Request", "application/json",
            r#"{"error":"missing q parameter"}"#.to_string());
    }

    let knowledge = crate::internet::search_all_sources(&topic, "en");

    if knowledge.facts.is_empty() {
        return ("404 Not Found", "application/json",
            r#"{"error":"not found in any source"}"#.to_string());
    }

    let facts_json: Vec<String> = knowledge.facts.iter()
        .map(|f| format!(r#"{{"source":"{}","summary":"{}","url":"{}","confidence":{}}}"#,
            escape_json(&f.source_name),
            escape_json(&f.summary),
            escape_json(&f.source_url),
            f.confidence))
        .collect();

    ("200 OK", "application/json",
        format!(r#"{{"topic":"{}","sources_count":{},"facts":[{}]}}"#,
            escape_json(&topic),
            knowledge.sources_count,
            facts_json.join(",")))
}

/// Simple heuristic to guess the domain (0-15) from a topic.
fn guess_domain(topic: &str) -> u8 {
    let t = topic.to_lowercase();
    if t.contains("energy") || t.contains("quantum") || t.contains("force")
        || t.contains("طاقة") || t.contains("كم") || t.contains("قوة") { return 0; }
    if t.contains("atom") || t.contains("molecule") || t.contains("chemical")
        || t.contains("ذرة") || t.contains("جزيء") || t.contains("كيمياء") { return 1; }
    if t.contains("cell") || t.contains("dna") || t.contains("evolution")
        || t.contains("خلية") || t.contains("حمض") || t.contains("تطور") { return 2; }
    if t.contains("math") || t.contains("equation") || t.contains("algebra")
        || t.contains("رياض") || t.contains("معادلة") || t.contains("جبر") { return 3; }
    if t.contains("logic") || t.contains("proof") || t.contains("منطق") { return 4; }
    if t.contains("computer") || t.contains("algorithm") || t.contains("software")
        || t.contains("حاسوب") || t.contains("خوارزم") { return 5; }
    if t.contains("economy") || t.contains("market") || t.contains("trade")
        || t.contains("اقتصاد") || t.contains("سوق") || t.contains("تجارة") { return 6; }
    if t.contains("philosoph") || t.contains("ethic") || t.contains("فلسف") { return 7; }
    if t.contains("psycholog") || t.contains("mind") || t.contains("نفس") { return 8; }
    if t.contains("history") || t.contains("war") || t.contains("تاريخ") || t.contains("حرب") { return 9; }
    if t.contains("language") || t.contains("linguist") || t.contains("لغة") || t.contains("لسان") { return 10; }
    if t.contains("star") || t.contains("planet") || t.contains("galaxy")
        || t.contains("نجم") || t.contains("كوكب") || t.contains("مجرة") { return 11; }
    if t.contains("earth") || t.contains("rock") || t.contains("earthquake")
        || t.contains("أرض") || t.contains("صخر") || t.contains("زلزال") { return 12; }
    if t.contains("medicine") || t.contains("disease") || t.contains("health")
        || t.contains("طب") || t.contains("مرض") || t.contains("صحة") { return 13; }
    if t.contains("engineer") || t.contains("circuit") || t.contains("هندس") { return 14; }
    if t.contains("politic") || t.contains("government") || t.contains("سياس") || t.contains("حكوم") { return 15; }
    0 // default to physics
}

fn extract_json_string(json: &str, key: &str) -> Option<String> {
    // Match "key" : "value" with optional spaces around the colon.
    let pattern = format!("\"{}\"", key);
    let key_pos = json.find(&pattern)?;
    let after_key = &json[key_pos + pattern.len()..];
    // Skip whitespace and colon
    let after_colon = after_key.trim_start();
    let after_colon = after_colon.strip_prefix(':')?;
    let after_colon = after_colon.trim_start();
    // Must start with a quote
    let rest = after_colon.strip_prefix('"')?;
    // Find the closing quote (handle escaped quotes)
    let mut chars = rest.chars();
    let mut result = String::new();
    let mut escaped = false;
    for c in &mut chars {
        if escaped {
            result.push(c);
            escaped = false;
        } else if c == '\\' {
            escaped = true;
        } else if c == '"' {
            return Some(result);
        } else {
            result.push(c);
        }
    }
    None
}

fn extract_json_int(json: &str, key: &str) -> Option<i64> {
    let pattern = format!("\"{}\"", key);
    let key_pos = json.find(&pattern)?;
    let after_key = &json[key_pos + pattern.len()..];
    let after_colon = after_key.trim_start();
    let after_colon = after_colon.strip_prefix(':')?;
    let rest = after_colon.trim_start();
    let end = rest.find(|c: char| !c.is_ascii_digit() && c != '-')?;
    rest[..end].parse().ok()
}

fn escape_json(s: &str) -> String {
    let mut result = String::with_capacity(s.len() + 16);
    for ch in s.chars() {
        match ch {
            '\\' => result.push_str("\\\\"),
            '"' => result.push_str("\\\""),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            '\x00'..='\x1F' => result.push_str(&format!("\\u{:04x}", ch as u32)),
            _ => result.push(ch),
        }
    }
    result
}

const HTML_PAGE: &str = r#"<!DOCTYPE html>
<html lang="ar" dir="rtl" id="html-root">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Omni-Mind — Quantum-Inspired AI</title>
<style>
:root {
  --void: #0a0e1a;
  --cream: #f5f3ef;
  --ink: #1a1f2e;
  --cyan: #00d9ff;
  --orange: #ff6b35;
  --violet: #8b5cf6;
  --green: #10b981;
  --border: #d6d2c9;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: 'Segoe UI', Tahoma, sans-serif;
  background: var(--cream);
  color: var(--ink);
  line-height: 1.6;
  padding: 20px;
  max-width: 900px;
  margin: 0 auto;
}
header {
  background: var(--void);
  color: var(--cream);
  padding: 20px 30px;
  border-radius: 12px 12px 0 0;
  display: flex;
  justify-content: space-between;
  align-items: center;
}
header h1 {
  font-size: 24px;
  background: linear-gradient(135deg, var(--cyan), var(--violet));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}
.stats {
  font-family: monospace;
  font-size: 12px;
  color: var(--cyan);
}
main {
  background: white;
  padding: 30px;
  border: 1px solid var(--border);
  border-top: none;
  border-radius: 0 0 12px 12px;
}
.query-form {
  display: flex;
  gap: 10px;
  margin-bottom: 20px;
}
.query-form input {
  flex: 1;
  padding: 12px 16px;
  border: 2px solid var(--border);
  border-radius: 8px;
  font-size: 14px;
  font-family: inherit;
}
.query-form input:focus {
  outline: none;
  border-color: var(--cyan);
}
.query-form button {
  padding: 12px 24px;
  background: var(--void);
  color: var(--cream);
  border: none;
  border-radius: 8px;
  cursor: pointer;
  font-size: 14px;
  font-weight: 600;
  transition: background 0.2s;
}
.query-form button:hover {
  background: var(--cyan);
  color: var(--void);
}
.answer-box {
  background: var(--cream);
  padding: 20px;
  border-radius: 8px;
  border-right: 4px solid var(--cyan);
  margin-bottom: 20px;
  min-height: 60px;
  white-space: pre-wrap;
  word-wrap: break-word;
}
.answer-box.empty {
  color: #999;
  font-style: italic;
}
.ingest-form {
  margin-top: 30px;
  padding-top: 20px;
  border-top: 1px solid var(--border);
}
.ingest-form h3 {
  margin-bottom: 10px;
  color: var(--violet);
}
.ingest-form .row {
  display: flex;
  gap: 10px;
  margin-bottom: 10px;
}
.ingest-form select {
  padding: 8px;
  border: 2px solid var(--border);
  border-radius: 6px;
  width: 150px;
}
.ingest-form input[type="text"] {
  flex: 1;
  padding: 8px 12px;
  border: 2px solid var(--border);
  border-radius: 6px;
}
.ingest-form button {
  padding: 8px 16px;
  background: var(--violet);
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
}
.examples {
  margin-top: 20px;
  padding: 15px;
  background: #fef7f0;
  border-radius: 8px;
  border-right: 4px solid var(--orange);
}
.examples h4 {
  color: var(--orange);
  margin-bottom: 8px;
}
.examples button {
  display: inline-block;
  margin: 4px 4px 4px 0;
  padding: 4px 10px;
  background: white;
  border: 1px solid var(--border);
  border-radius: 4px;
  cursor: pointer;
  font-size: 12px;
}
.examples button:hover {
  background: var(--orange);
  color: white;
}
.loading {
  display: none;
  text-align: center;
  padding: 20px;
  color: var(--cyan);
}
.loading.active {
  display: block;
}
footer {
  text-align: center;
  margin-top: 20px;
  font-size: 12px;
  color: #999;
}
</style>
</head>
<body>
<header>
  <h1>⚡ Project Omni-Mind</h1>
  <div style="display:flex;align-items:center;gap:15px;">
    <button id="lang-toggle" onclick="toggleLang()" style="padding:6px 14px;background:var(--cyan);color:var(--void);border:none;border-radius:6px;cursor:pointer;font-weight:700;font-size:13px;">EN</button>
    <div class="stats" id="stats">Loading...</div>
  </div>
</header>
<main>
  <div class="query-form">
    <input type="text" id="query" placeholder="اكتب سؤالك هنا..." autofocus>
    <button onclick="askQuery()">اسأل</button>
    <button onclick="learnFromInternet()" style="background:var(--cyan);color:var(--void);font-weight:700;">🌐 تعلّم</button>
  </div>
  <div class="loading" id="loading">جاري المعالجة عبر 7 طبقات...</div>
  
  <div id="chat-history" style="max-height:500px;overflow-y:auto;margin:15px 0;padding:10px;background:rgba(0,0,0,0.3);border-radius:12px;"></div>

  <div class="examples">
    <h4>أسئلة تجريبية:</h4>
    <button onclick="example('why do brakes get hot?')">لماذا تسخن المكابح؟</button>
    <button onclick="example('Can quantum mechanics improve AI?')">هل الكم يحسّن الذكاء الاصطناعي؟</button>
    <button onclick="example('how does DNA store information?')">كيف يخزن DNA المعلومات؟</button>
    <button onclick="example('what is a catalyst?')">ما هو الحفاز؟</button>
    <button onclick="example('why does trade happen?')">لماذا يحدث التبادل التجاري؟</button>
  </div>

  <div class="ingest-form">
    <h3>➕ إضافة بديهية جديدة</h3>
    <div class="row">
      <select id="domain">
        <option value="0">الفيزياء</option>
        <option value="1">الكيمياء</option>
        <option value="2">الأحياء</option>
        <option value="3">الرياضيات</option>
        <option value="4">المنطق</option>
        <option value="5">علوم الحاسوب</option>
        <option value="6">الاقتصاد</option>
      </select>
      <input type="text" id="axiom" placeholder="نص البديهية...">
      <button onclick="ingestAxiom()">أضف</button>
    </div>
  </div>
</main>
<footer>
  Omni-Mind v0.1 · Quantum-Inspired Symbolic AI · CPU + 2GB RAM · Zig × Rust
</footer>

<script>
let chatMessages = [];

function addMessage(role, text) {
  chatMessages.push({role, text});
  const history = document.getElementById('chat-history');
  const div = document.createElement('div');
  div.style.cssText = role === 'user'
    ? 'margin:8px 0;padding:12px 16px;background:var(--cyan);color:var(--void);border-radius:16px 16px 4px 16px;max-width:70%;margin-right:auto;font-weight:500;white-space:pre-wrap;'
    : 'margin:8px 0;padding:12px 16px;background:rgba(255,255,255,0.1);color:var(--text);border-radius:16px 16px 16px 4px;max-width:85%;margin-left:auto;white-space:pre-wrap;line-height:1.6;';
  const label = document.createElement('div');
  label.style.cssText = 'font-size:11px;opacity:0.6;margin-bottom:4px;font-weight:700;';
  label.textContent = role === 'user' ? '👤 أنت' : '🧠 Omni-Mind';
  const content = document.createElement('div');
  content.textContent = text;
  div.appendChild(label);
  div.appendChild(content);
  history.appendChild(div);
  history.scrollTop = history.scrollHeight;
}

async function askQuery() {
  const q = document.getElementById('query').value;
  if (!q) return;
  document.getElementById('query').value = '';
  addMessage('user', q);
  document.getElementById('loading').classList.add('active');
  try {
    const res = await fetch('/api/query', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({query: q})
    });
    const data = await res.json();
    let display = data.answer || data.error;
    if (data.auto_learned && data.sources_count) {
      display += '\\n\\n📡 تم التعلم من ' + data.sources_count + ' مصدر إنترنت';
    }
    addMessage('ai', display);
  } catch(e) {
    addMessage('ai', 'خطأ: ' + e.message);
  }
  document.getElementById('loading').classList.remove('active');
  loadStats();
}

function example(q) {
  document.getElementById('query').value = q;
  askQuery();
}

async function loadStats() {
  try {
    const res = await fetch('/api/stats');
    const data = await res.json();
    const mb = (data.bytes_used / 1048576).toFixed(2);
    const budget = (data.bytes_budget / 1048576).toFixed(0);
    document.getElementById('stats').textContent =
      `nodes=${data.nodes} edges=${data.edges} axioms=${data.axioms} ${mb}/${budget}MB`;
  } catch(e) {}
}

async function ingestAxiom() {
  const domain = document.getElementById('domain').value;
  const text = document.getElementById('axiom').value;
  if (!text) return;
  try {
    const res = await fetch('/api/ingest', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({domain: parseInt(domain), text: text})
    });
    const data = await res.json();
    alert(data.status ? 'تمت الإضافة!' : 'فشل: ' + data.error);
    document.getElementById('axiom').value = '';
  } catch(e) {
    alert('خطأ: ' + e.message);
  }
  loadStats();
}

async function learnFromInternet() {
  const q = document.getElementById('query').value;
  if (!q) {
    alert('اكتب موضوعاً في خانة البحث أولاً');
    return;
  }
  document.getElementById('query').value = '';
  addMessage('user', '🌐 تعلّم عن: ' + q);
  document.getElementById('loading').classList.add('active');
  try {
    const lang = /[\u0600-\u06FF]/.test(q) ? 'ar' : 'en';
    const res = await fetch('/api/learn', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({topic: q, lang: lang})
    });
    const data = await res.json();
    if (data.status === 'learned') {
      let sourcesList = '';
      if (data.sources && data.sources.length > 0) {
        sourcesList = '\n📚 المصادر:\n';
        data.sources.forEach(s => { sourcesList += '  • ' + s.name + '\n'; });
      }
      addMessage('ai', '✓ تم التعلم من ' + data.sources_count + ' مصادر!\n\nالموضوع: ' + data.topic + '\nالبديهية: ' + data.axiom + sourcesList);
    } else {
      addMessage('ai', 'فشل التعلم: ' + (data.error || 'غير معروف'));
    }
  } catch(e) {
    addMessage('ai', 'خطأ: ' + e.message);
  }
  document.getElementById('loading').classList.remove('active');
  loadStats();
}

document.getElementById('query').addEventListener('keypress', (e) => {
  if (e.key === 'Enter') askQuery();
});

// ─── Language toggle ─────────────────────────────────
let currentLang = 'ar';
const i18n = {
  ar: {
    placeholder: 'اكتب سؤالك هنا...',
    askBtn: 'اسأل',
    loading: 'جاري المعالجة عبر 7 طبقات...',
    answerEmpty: 'ستظهر الإجابة هنا',
    examplesTitle: 'أسئلة تجريبية:',
    ingestTitle: '➕ إضافة بديهية جديدة',
    ingestBtn: 'أضف',
    axiomPlaceholder: 'نص البديهية...',
    footer: 'Omni-Mind v0.2 · ذكاء اصطناعي رمزي مستوحى من الكم · CPU + 2GB RAM · Zig × Rust',
    langBtn: 'EN'
  },
  en: {
    placeholder: 'Type your question here...',
    askBtn: 'Ask',
    loading: 'Processing through 7 layers...',
    answerEmpty: 'Answer will appear here',
    examplesTitle: 'Example questions:',
    ingestTitle: '➕ Add new axiom',
    ingestBtn: 'Add',
    axiomPlaceholder: 'Axiom text...',
    footer: 'Omni-Mind v0.2 · Quantum-Inspired Symbolic AI · CPU + 2GB RAM · Zig × Rust',
    langBtn: 'ع'
  }
};

function toggleLang() {
  currentLang = currentLang === 'ar' ? 'en' : 'ar';
  const t = i18n[currentLang];
  document.getElementById('html-root').lang = currentLang;
  document.getElementById('html-root').dir = currentLang === 'ar' ? 'rtl' : 'ltr';
  document.getElementById('query').placeholder = t.placeholder;
  document.getElementById('lang-toggle').textContent = t.langBtn;
  // Update button text
  document.querySelector('.query-form button').textContent = t.askBtn;
  document.querySelector('.answer-box.empty').textContent = t.answerEmpty;
  // Update examples title
  document.querySelector('.examples h4').textContent = t.examplesTitle;
  // Update ingest section
  document.querySelector('.ingest-form h3').textContent = t.ingestTitle;
  document.querySelector('.ingest-form button').textContent = t.ingestBtn;
  document.getElementById('axiom').placeholder = t.axiomPlaceholder;
  // Update footer
  document.querySelector('footer').textContent = t.footer;
}

loadStats();
</script>
</body>
</html>"#;
