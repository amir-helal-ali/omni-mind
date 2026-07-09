//! src/internet.rs — Internet Learning Module
//!
//! Enables Omni-Mind to learn from the internet in real-time.
//! Uses Wikipedia API (free, no key required, multilingual).
//!
//! When the system can't answer a question confidently, or when the user
//! asks it to learn about a topic, this module:
//!   1. Searches Wikipedia for the topic (in detected language)
//!   2. Fetches the article summary
//!   3. Extracts key sentences as candidate axioms
//!   4. Ingests them into the knowledge base
//!
//! This makes Omni-Mind a living system that grows its knowledge on demand.

use std::io::Read;
use std::net::TcpStream;
use std::time::Duration;

/// A piece of knowledge learned from the internet.
#[derive(Debug, Clone)]
pub struct InternetFact {
    pub topic: String,
    pub summary: String,
    pub source_url: String,
    pub language: String,
    pub confidence: f32,
}

/// Search Wikipedia and return a summary of the article.
/// Returns None if the article doesn't exist or network fails.
pub fn search_wikipedia(topic: &str, language: &str) -> Option<InternetFact> {
    let lang = if language.starts_with("ar") { "ar" } else { "en" };
    let host = if lang == "ar" { "ar.wikipedia.org" } else { "en.wikipedia.org" };

    log::info!("Searching Wikipedia ({}) for: {}", lang, topic);

    // Use the REST API summary endpoint — returns plain text extract.
    // Path: /api/rest_v1/page/summary/{title}
    let encoded_topic = url_encode(topic);
    let path = format!("/api/rest_v1/page/summary/{}", encoded_topic);

    let body = https_get(host, &path)?;
    let summary = extract_wikipedia_summary(&body)?;

    if summary.len() < 20 {
        return None;
    }

    let source_url = format!("https://{}/wiki/{}", host, encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary,
        source_url,
        language: lang.to_string(),
        confidence: 0.7, // Wikipedia is generally reliable
    })
}

/// Search Wikipedia's search API for multiple results.
pub fn search_wikipedia_multi(topic: &str, language: &str, limit: usize) -> Vec<InternetFact> {
    let lang = if language.starts_with("ar") { "ar" } else { "en" };
    let host = if lang == "ar" { "ar.wikipedia.org" } else { "en.wikipedia.org" };

    log::info!("Searching Wikipedia ({}) for multiple results: {}", lang, topic);

    // Use the MediaWiki action API for search.
    let encoded_topic = url_encode(topic);
    let path = format!(
        "/w/api.php?action=query&list=search&srsearch={}&srlimit={}&format=json&utf8=1",
        encoded_topic, limit
    );

    let body = match https_get(host, &path) {
        Some(b) => b,
        None => return Vec::new(),
    };

    // Extract page titles from JSON response.
    let titles = extract_search_titles(&body);
    let mut facts = Vec::new();

    for title in titles.iter().take(limit) {
        if let Some(fact) = search_wikipedia(title, lang) {
            facts.push(fact);
        }
    }

    facts
}

/// Convert an InternetFact into axiom-ready text.
/// Takes the first 2-3 sentences of the summary as the axiom text.
pub fn fact_to_axiom_text(fact: &InternetFact) -> String {
    // Take the first ~200 characters or first 2 sentences.
    let summary = &fact.summary;

    // Find sentence boundaries (handles both English . and Arabic ؟)
    let mut end = summary.len().min(250);
    let mut sentence_count = 0;

    for (i, ch) in summary.char_indices() {
        if ch == '.' || ch == '؟' || ch == '!' {
            sentence_count += 1;
            if sentence_count >= 2 {
                end = i + 1;
                break;
            }
        }
    }

    let text = summary[..end].trim();
    text.to_string()
}

/// Perform an HTTPS GET request using native TCP + TLS via shell-out to curl.
fn https_get(host: &str, path: &str) -> Option<String> {
    // Try curl first (most reliable for HTTPS).
    let url = format!("https://{}{}", host, path);
    if let Some(body) = curl_get(&url) {
        return Some(body);
    }

    // Fallback: try native HTTP (won't work for HTTPS, but try anyway).
    log::warn!("curl failed, trying native HTTP (may not work for HTTPS)");
    native_http_get(host, path)
}

/// Use curl to fetch a URL.
fn curl_get(url: &str) -> Option<String> {
    use std::process::Command;

    let output = Command::new("curl")
        .args(&[
            "-s",
            "-L",
            "--max-time", "10",
            "-H", "User-Agent: Omni-Mind/0.2 (educational AI project)",
            "-H", "Accept: application/json",
            url,
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        log::warn!("curl exited with status: {}", output.status);
        return None;
    }

    let body = String::from_utf8_lossy(&output.stdout).to_string();
    if body.is_empty() {
        return None;
    }

    Some(body)
}

/// Native HTTP/1.1 GET (no TLS — use for HTTP endpoints only).
fn native_http_get(host: &str, path: &str) -> Option<String> {
    let port = 80;
    let addr = format!("{}:{}", host, port);

    let mut stream = TcpStream::connect_timeout(
        &addr.parse().ok()?,
        Duration::from_secs(10),
    ).ok()?;

    stream.set_read_timeout(Some(Duration::from_secs(10))).ok()?;
    stream.set_write_timeout(Some(Duration::from_secs(10))).ok()?;

    let request = format!(
        "GET {} HTTP/1.1\r\nHost: {}\r\nUser-Agent: Omni-Mind/0.2\r\nAccept: application/json\r\nConnection: close\r\n\r\n",
        path, host
    );

    use std::io::Write;
    stream.write_all(request.as_bytes()).ok()?;

    let mut response = String::new();
    stream.read_to_string(&mut response).ok()?;

    // Skip HTTP headers.
    if let Some(pos) = response.find("\r\n\r\n") {
        Some(response[pos + 4..].to_string())
    } else {
        Some(response)
    }
}

/// Extract the summary extract from a Wikipedia REST API JSON response.
fn extract_wikipedia_summary(json: &str) -> Option<String> {
    // Look for "extract":"..." in the JSON.
    // This is a simple parser — we don't need a full JSON library.
    let key = "\"extract\":\"";
    let start = json.find(key)? + key.len();

    // Find the closing quote (handle escaped quotes).
    let mut end = start;
    let mut i = start;
    let bytes = json.as_bytes();
    while i < bytes.len() {
        if bytes[i] == b'\\' {
            i += 2; // Skip escaped character
            continue;
        }
        if bytes[i] == b'"' {
            end = i;
            break;
        }
        i += 1;
    }

    if end <= start {
        return None;
    }

    let raw = &json[start..end];

    // Unescape JSON string escapes.
    let summary = raw
        .replace("\\n", " ")
        .replace("\\\"", "\"")
        .replace("\\'", "'")
        .replace("\\\\", "\\");

    if summary.len() < 10 {
        return None;
    }

    Some(summary)
}

/// Extract page titles from a Wikipedia search API JSON response.
fn extract_search_titles(json: &str) -> Vec<String> {
    let mut titles = Vec::new();

    // Look for "title":"..." patterns.
    let key = "\"title\":\"";
    let mut pos = 0;
    while pos < json.len() {
        if let Some(found) = json[pos..].find(key) {
            let start = pos + found + key.len();
            if start >= json.len() {
                break;
            }
            // Find closing quote.
            let mut end = start;
            let bytes = json.as_bytes();
            let mut i = start;
            while i < bytes.len() {
                if bytes[i] == b'\\' {
                    i += 2;
                    continue;
                }
                if bytes[i] == b'"' {
                    end = i;
                    break;
                }
                i += 1;
            }
            if end > start {
                let title = &json[start..end];
                titles.push(title.replace("\\\"", "\"").replace("\\\\", "\\"));
            }
            pos = end + 1;
        } else {
            break;
        }
    }

    titles
}

/// URL-encode a string for use in a URL path.
fn url_encode(s: &str) -> String {
    let mut result = String::new();
    for byte in s.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                result.push(byte as char);
            }
            b' ' => result.push_str("%20"),
            _ => {
                result.push_str(&format!("%{:02X}", byte));
            }
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_encode_works() {
        assert_eq!(url_encode("hello world"), "hello%20world");
        assert_eq!(url_encode("الطاقة"), "%D8%A7%D9%84%D8%B7%D8%A7%D9%82%D8%A9");
    }

    #[test]
    fn extract_summary_parses_json() {
        let json = r#"{"extract":"Energy is the quantitative property that is transferred to a body or to a physical system."}"#;
        let summary = extract_wikipedia_summary(json).unwrap();
        assert!(summary.contains("Energy"));
    }

    #[test]
    fn fact_to_axiom_truncates() {
        let fact = InternetFact {
            topic: "test".to_string(),
            summary: "First sentence. Second sentence. Third sentence that is very long and should be cut off.".to_string(),
            source_url: "http://example.com".to_string(),
            language: "en".to_string(),
            confidence: 0.7,
        };
        let axiom = fact_to_axiom_text(&fact);
        assert!(axiom.contains("First sentence"));
        assert!(axiom.contains("Second sentence"));
    }
}
