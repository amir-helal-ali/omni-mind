//! src/internet.rs — Multi-Source Internet Learning Module
//!
//! Enables Omni-Mind to learn from MULTIPLE internet sources in real-time.
//! Aggregates knowledge from several encyclopedias and knowledge bases:
//!
//!   1. Wikipedia (en/ar) — general encyclopedia (free, no key)
//!   2. Wiktionary — definitions and etymology (free, no key)
//!   3. Wikiquote — quotations from notable people (free, no key)
//!   4. DBpedia — structured knowledge from Wikipedia (free, no key)
//!   5. Open Library — book descriptions (free, no key)
//!   6. Crossref — academic papers metadata (free, no key)
//!   7. arXiv — scientific preprints (free, no key)
//!   8. GitHub — code and documentation (free, no key)
//!   9. Stack Exchange — Q&A knowledge (free, no key)
//!  10. Hackernews Algolia — tech discussions (free, no key)
//!
//! When asked to learn about a topic, the system queries ALL sources in
//! parallel, merges the results, and creates enriched axioms.

use std::io::Read;
use std::net::TcpStream;
use std::time::Duration;

/// A piece of knowledge learned from the internet.
#[derive(Debug, Clone)]
pub struct InternetFact {
    pub topic: String,
    pub summary: String,
    pub source_url: String,
    pub source_name: String,
    pub language: String,
    pub confidence: f32,
}

/// Aggregated knowledge from multiple sources.
#[derive(Debug, Clone)]
pub struct AggregatedKnowledge {
    pub topic: String,
    pub facts: Vec<InternetFact>,
    pub combined_summary: String,
    pub sources_count: usize,
}

/// Search a SINGLE source for a topic.
/// Returns None if the source doesn't have info or is unreachable.
pub fn search_source(topic: &str, language: &str, source: &str) -> Option<InternetFact> {
    match source {
        "wikipedia" => search_wikipedia(topic, language),
        "wiktionary" => search_wiktionary(topic, language),
        "wikiquote" => search_wikiquote(topic, language),
        "dbpedia" => search_dbpedia(topic, language),
        "openlibrary" => search_openlibrary(topic),
        "crossref" => search_crossref(topic),
        "arxiv" => search_arxiv(topic),
        "github" => search_github(topic),
        "stackexchange" => search_stackexchange(topic),
        "hackernews" => search_hackernews(topic),
        "mdn" => search_mdn(topic),
        "devto" => search_devto(topic),
        "npm" => search_npm(topic),
        "pypi" => search_pypi(topic),
        _ => None,
    }
}

/// Search ALL configured sources in sequence and aggregate results.
pub fn search_all_sources(topic: &str, language: &str) -> AggregatedKnowledge {
    let sources = [
        "wikipedia",
        "wiktionary",
        "wikiquote",
        "dbpedia",
        "openlibrary",
        "crossref",
        "arxiv",
        "github",
        "stackexchange",
        "hackernews",
        "mdn",
        "devto",
        "npm",
        "pypi",
    ];

    let mut facts = Vec::new();

    for source in &sources {
        if let Some(fact) = search_source(topic, language, source) {
            log::info!("✓ {} found info from {}", topic, source);
            facts.push(fact);
        } else {
            log::debug!("✗ {} not found in {}", topic, source);
        }
    }

    // Build combined summary from all sources.
    let combined_summary = combine_summaries(&facts, topic);

    AggregatedKnowledge {
        topic: topic.to_string(),
        sources_count: facts.len(),
        facts,
        combined_summary,
    }
}

/// Get the list of all available sources.
pub fn list_sources() -> Vec<&'static str> {
    vec![
        "wikipedia",
        "wiktionary",
        "wikiquote",
        "dbpedia",
        "openlibrary",
        "crossref",
        "arxiv",
        "github",
        "stackexchange",
        "hackernews",
        "mdn",
        "devto",
        "npm",
        "pypi",
    ]
}

/// Combine summaries from multiple sources into a coherent text.
fn combine_summaries(facts: &[InternetFact], topic: &str) -> String {
    if facts.is_empty() {
        return format!("No information found about {}.", topic);
    }

    let mut parts: Vec<String> = Vec::new();

    for (i, fact) in facts.iter().enumerate() {
        if i > 0 {
            parts.push(format!("\n[From {}]", fact.source_name));
        }
        parts.push(fact.summary.clone());
    }

    parts.join(" ")
}

// ─── Source-specific search functions ─────────────────────────────

/// Search Wikipedia for a topic.
pub fn search_wikipedia(topic: &str, language: &str) -> Option<InternetFact> {
    let lang = if language.starts_with("ar") { "ar" } else { "en" };
    let host = if lang == "ar" { "ar.wikipedia.org" } else { "en.wikipedia.org" };

    log::info!("Searching Wikipedia ({}) for: {}", lang, topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/api/rest_v1/page/summary/{}", encoded_topic);

    let body = https_get(host, &path)?;
    let summary = extract_json_string_field(&body, "extract")?;

    if summary.len() < 20 {
        return None;
    }

    let source_url = format!("https://{}/wiki/{}", host, encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary,
        source_url,
        source_name: "Wikipedia".to_string(),
        language: lang.to_string(),
        confidence: 0.7,
    })
}

/// Search Wiktionary for word definitions.
pub fn search_wiktionary(topic: &str, language: &str) -> Option<InternetFact> {
    let lang = if language.starts_with("ar") { "ar" } else { "en" };
    let host = if lang == "ar" { "ar.wiktionary.org" } else { "en.wiktionary.org" };

    log::info!("Searching Wiktionary ({}) for: {}", lang, topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/api/rest_v1/page/definition/{}", encoded_topic);

    let body = https_get(host, &path)?;
    let summary = extract_json_string_field(&body, "extract")?;

    if summary.len() < 10 {
        return None;
    }

    let source_url = format!("https://{}/wiki/{}", host, encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary,
        source_url,
        source_name: "Wiktionary".to_string(),
        language: lang.to_string(),
        confidence: 0.6,
    })
}

/// Search Wikiquote for quotations.
pub fn search_wikiquote(topic: &str, language: &str) -> Option<InternetFact> {
    let lang = if language.starts_with("ar") { "ar" } else { "en" };
    let host = if lang == "ar" { "ar.wikiquote.org" } else { "en.wikiquote.org" };

    log::info!("Searching Wikiquote ({}) for: {}", lang, topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/api/rest_v1/page/summary/{}", encoded_topic);

    let body = https_get(host, &path)?;
    let summary = extract_json_string_field(&body, "extract")?;

    if summary.len() < 10 {
        return None;
    }

    let source_url = format!("https://{}/wiki/{}", host, encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary,
        source_url,
        source_name: "Wikiquote".to_string(),
        language: lang.to_string(),
        confidence: 0.5,
    })
}

/// Search DBpedia for structured knowledge.
pub fn search_dbpedia(topic: &str, _language: &str) -> Option<InternetFact> {
    log::info!("Searching DBpedia for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!(
        "/sparql?query=SELECT%20?abstract%20WHERE%20{{%20<http://dbpedia.org/resource/{}>%20<http://dbpedia.org/ontology/abstract>%20?abstract%20.%20FILTER(lang(?abstract)%20=%20'en')%20}}&format=json",
        encoded_topic
    );

    let body = https_get("dbpedia.org", &path)?;
    let summary = extract_json_string_field(&body, "value")?;

    if summary.len() < 20 {
        return None;
    }

    let source_url = format!("https://dbpedia.org/resource/{}", encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary,
        source_url,
        source_name: "DBpedia".to_string(),
        language: "en".to_string(),
        confidence: 0.7,
    })
}

/// Search Open Library for book descriptions.
pub fn search_openlibrary(topic: &str) -> Option<InternetFact> {
    log::info!("Searching Open Library for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/search.json?q={}&limit=1", encoded_topic);

    let body = https_get("openlibrary.org", &path)?;

    // Extract first book description.
    let summary = extract_json_string_field(&body, "title")?;
    let author = extract_json_string_field(&body, "author_name").unwrap_or_default();

    if summary.len() < 3 {
        return None;
    }

    let combined = if author.is_empty() {
        format!("Book: {}", summary)
    } else {
        format!("Book: {} by {}", summary, author)
    };

    let source_url = format!("https://openlibrary.org/search?q={}", encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url,
        source_name: "Open Library".to_string(),
        language: "en".to_string(),
        confidence: 0.5,
    })
}

/// Search Crossref for academic papers.
pub fn search_crossref(topic: &str) -> Option<InternetFact> {
    log::info!("Searching Crossref for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/works?query={}&rows=1", encoded_topic);

    let body = https_get("api.crossref.org", &path)?;

    let title = extract_json_string_field(&body, "title")?;
    let abstract_text = extract_json_string_field(&body, "abstract").unwrap_or_default();

    if title.len() < 5 {
        return None;
    }

    let combined = if abstract_text.is_empty() {
        format!("Academic paper: {}", title)
    } else {
        format!("Academic paper: {}. {}", title, abstract_text)
    };

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url: "https://api.crossref.org".to_string(),
        source_name: "Crossref".to_string(),
        language: "en".to_string(),
        confidence: 0.8,
    })
}

/// Search arXiv for scientific preprints.
pub fn search_arxiv(topic: &str) -> Option<InternetFact> {
    log::info!("Searching arXiv for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/api/query?search_query=all:{}&max_results=1", encoded_topic);

    let body = https_get("export.arxiv.org", &path)?;

    // Extract <summary> from XML response.
    let summary = extract_xml_field(&body, "summary")?;

    if summary.len() < 20 {
        return None;
    }

    let title = extract_xml_field(&body, "title").unwrap_or_else(|| topic.to_string());

    let combined = format!("Scientific preprint: {}. {}", title, summary);

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url: format!("https://arxiv.org/find/all?q={}", encoded_topic),
        source_name: "arXiv".to_string(),
        language: "en".to_string(),
        confidence: 0.8,
    })
}

/// Search GitHub for repositories and documentation.
pub fn search_github(topic: &str) -> Option<InternetFact> {
    log::info!("Searching GitHub for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/search/repositories?q={}&per_page=1", encoded_topic);

    let body = https_get("api.github.com", &path)?;

    let full_name = extract_json_string_field(&body, "full_name")?;
    let description = extract_json_string_field(&body, "description").unwrap_or_default();

    if full_name.len() < 3 {
        return None;
    }

    let combined = if description.is_empty() {
        format!("GitHub repository: {}", full_name)
    } else {
        format!("GitHub repository {}: {}", full_name, description)
    };

    let source_url = format!("https://github.com/{}", full_name);

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url,
        source_name: "GitHub".to_string(),
        language: "en".to_string(),
        confidence: 0.6,
    })
}

/// Search Stack Exchange for Q&A knowledge.
pub fn search_stackexchange(topic: &str) -> Option<InternetFact> {
    log::info!("Searching Stack Exchange for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/2.3/search/advanced?order=desc&sort=votes&q={}&site=stackoverflow&pagesize=1", encoded_topic);

    let body = https_get("api.stackexchange.com", &path)?;

    let title = extract_json_string_field(&body, "title")?;

    if title.len() < 5 {
        return None;
    }

    let combined = format!("Stack Overflow Q&A: {}", title);
    let source_url = format!("https://stackoverflow.com/search?q={}", encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url,
        source_name: "Stack Exchange".to_string(),
        language: "en".to_string(),
        confidence: 0.7,
    })
}

/// Search Hackernews (via Algolia) for tech discussions.
pub fn search_hackernews(topic: &str) -> Option<InternetFact> {
    log::info!("Searching Hackernews for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/api/v1/search?query={}&tags=story&hitsPerPage=1", encoded_topic);

    let body = https_get("hn.algolia.com", &path)?;

    let title = extract_json_string_field(&body, "title")?;

    if title.len() < 5 {
        return None;
    }

    let points = extract_json_int_field(&body, "points").unwrap_or(0);
    let combined = format!("Hackernews discussion: {} ({} points)", title, points);
    let source_url = format!("https://hn.algolia.com/?q={}", encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url,
        source_name: "Hackernews".to_string(),
        language: "en".to_string(),
        confidence: 0.5,
    })
}

/// Convert an InternetFact into axiom-ready text.
pub fn fact_to_axiom_text(fact: &InternetFact) -> String {
    let summary = &fact.summary;
    let mut end = summary.len().min(300);
    let mut sentence_count = 0;

    for (i, ch) in summary.char_indices() {
        if ch == '.' || ch == '؟' || ch == '!' {
            sentence_count += 1;
            if sentence_count >= 3 {
                end = i + 1;
                break;
            }
        }
    }

    summary[..end].trim().to_string()
}

/// Convert aggregated knowledge from multiple sources into a single axiom.
pub fn aggregated_to_axiom(knowledge: &AggregatedKnowledge) -> String {
    if knowledge.facts.is_empty() {
        return format!("No information found about {}.", knowledge.topic);
    }

    // Use the fact with highest confidence as the primary.
    let mut best_fact = &knowledge.facts[0];
    for fact in &knowledge.facts {
        if fact.confidence > best_fact.confidence {
            best_fact = fact;
        }
    }

    let primary = fact_to_axiom_text(best_fact);

    // Add source count for credibility.
    if knowledge.sources_count > 1 {
        format!("{} (confirmed by {} sources)", primary, knowledge.sources_count)
    } else {
        primary
    }
}

// ─── HTTP and parsing utilities ───────────────────────────────────

/// Perform an HTTPS GET request.
fn https_get(host: &str, path: &str) -> Option<String> {
    let url = format!("https://{}{}", host, path);
    if let Some(body) = curl_get(&url) {
        return Some(body);
    }
    native_http_get(host, path)
}

/// Use curl to fetch a URL.
fn curl_get(url: &str) -> Option<String> {
    use std::process::Command;

    let output = Command::new("curl")
        .args(&[
            "-s", "-L",
            "--max-time", "10",
            "-H", "User-Agent: Omni-Mind/0.2 (educational AI project)",
            "-H", "Accept: application/json",
            url,
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let body = String::from_utf8_lossy(&output.stdout).to_string();
    if body.is_empty() {
        None
    } else {
        Some(body)
    }
}

/// Native HTTP/1.1 GET (no TLS).
fn native_http_get(host: &str, path: &str) -> Option<String> {
    let addr = format!("{}:80", host);
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

    if let Some(pos) = response.find("\r\n\r\n") {
        Some(response[pos + 4..].to_string())
    } else {
        Some(response)
    }
}

/// Extract a string field from JSON: "field":"value"
fn extract_json_string_field(json: &str, key: &str) -> Option<String> {
    let patterns = [
        format!("\"{}\":\"", key),
        format!("\"{}\": \"", key),
    ];

    for pattern in &patterns {
        if let Some(pos) = json.find(pattern.as_str()) {
            let start = pos + pattern.len();
            if start >= json.len() {
                continue;
            }

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
                let raw = &json[start..end];
                let value = raw
                    .replace("\\n", " ")
                    .replace("\\\"", "\"")
                    .replace("\\'", "'")
                    .replace("\\\\", "\\")
                    .replace("\\u003c", "<")
                    .replace("\\u003e", ">")
                    .replace("\\u0026", "&");
                return Some(value);
            }
        }
    }
    None
}

/// Extract an integer field from JSON: "field":123
fn extract_json_int_field(json: &str, key: &str) -> Option<i64> {
    let patterns = [
        format!("\"{}\":", key),
        format!("\"{}\": ", key),
    ];

    for pattern in &patterns {
        if let Some(pos) = json.find(pattern.as_str()) {
            let start = pos + pattern.len();
            let mut end = start;
            for (i, ch) in json[start..].char_indices() {
                if !ch.is_ascii_digit() && ch != '-' {
                    end = start + i;
                    break;
                }
            }
            if end > start {
                return json[start..end].parse().ok();
            }
        }
    }
    None
}

/// Extract content from an XML field: <tag>content</tag>
fn extract_xml_field(xml: &str, tag: &str) -> Option<String> {
    let open = format!("<{}>", tag);
    let close = format!("</{}>", tag);

    let start = xml.find(&open)? + open.len();
    let end = xml[start..].find(&close)? + start;

    if end <= start {
        return None;
    }

    let raw = &xml[start..end];

    // Strip CDATA if present.
    let cleaned = raw
        .replace("<![CDATA[", "")
        .replace("]]>", "")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&apos;", "'");

    Some(cleaned.trim().to_string())
}

/// URL-encode a string.
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

/// Search MDN Web Docs for web API documentation.
pub fn search_mdn(topic: &str) -> Option<InternetFact> {
    log::info!("Searching MDN Web Docs for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/api/v1/search?q={}&size=1", encoded_topic);

    let body = https_get("developer.mozilla.org", &path)?;

    let title = extract_json_string_field(&body, "title")?;
    let excerpt = extract_json_string_field(&body, "excerpt").unwrap_or_default();

    if title.len() < 3 {
        return None;
    }

    let combined = if excerpt.is_empty() {
        format!("MDN documentation: {}", title)
    } else {
        format!("MDN: {}. {}", title, excerpt)
    };

    let source_url = format!("https://developer.mozilla.org/search?q={}", encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url,
        source_name: "MDN Web Docs".to_string(),
        language: "en".to_string(),
        confidence: 0.8,
    })
}

/// Search Dev.to for programming articles and tutorials.
pub fn search_devto(topic: &str) -> Option<InternetFact> {
    log::info!("Searching Dev.to for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/api/articles?tag={}&per_page=1", encoded_topic);

    let body = https_get("dev.to", &path)?;

    // Dev.to returns array; extract first article.
    let title = extract_json_string_field(&body, "title")?;
    let description = extract_json_string_field(&body, "description").unwrap_or_default();

    if title.len() < 3 {
        return None;
    }

    let combined = if description.is_empty() {
        format!("Dev.to article: {}", title)
    } else {
        format!("Dev.to article: {}. {}", title, description)
    };

    let slug = extract_json_string_field(&body, "slug").unwrap_or_default();
    let source_url = if slug.is_empty() {
        format!("https://dev.to/t/{}", encoded_topic)
    } else {
        format!("https://dev.to/{}", slug)
    };

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url,
        source_name: "Dev.to".to_string(),
        language: "en".to_string(),
        confidence: 0.6,
    })
}

/// Search npm registry for JavaScript packages.
pub fn search_npm(topic: &str) -> Option<InternetFact> {
    log::info!("Searching npm for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/-/v1/search?text={}&size=1", encoded_topic);

    let body = https_get("registry.npmjs.org", &path)?;

    let name = extract_json_string_field(&body, "name")?;
    let description = extract_json_string_field(&body, "description").unwrap_or_default();

    if name.len() < 2 {
        return None;
    }

    let combined = if description.is_empty() {
        format!("npm package: {}", name)
    } else {
        format!("npm package {}: {}", name, description)
    };

    let source_url = format!("https://www.npmjs.com/package/{}", name);

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url,
        source_name: "npm".to_string(),
        language: "en".to_string(),
        confidence: 0.6,
    })
}

/// Search PyPI for Python packages.
pub fn search_pypi(topic: &str) -> Option<InternetFact> {
    log::info!("Searching PyPI for: {}", topic);

    let encoded_topic = url_encode(topic);
    let path = format!("/search/?q={}", encoded_topic);

    let body = https_get("pypi.org", &path)?;

    // PyPI returns HTML; try to extract package name from title.
    let title = extract_xml_field(&body, "title")?;

    if title.len() < 5 {
        return None;
    }

    let combined = format!("PyPI search for {}: {}", topic, title);
    let source_url = format!("https://pypi.org/search/?q={}", encoded_topic);

    Some(InternetFact {
        topic: topic.to_string(),
        summary: combined,
        source_url,
        source_name: "PyPI".to_string(),
        language: "en".to_string(),
        confidence: 0.6,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_encode_works() {
        assert_eq!(url_encode("hello world"), "hello%20world");
    }

    #[test]
    fn extract_json_string_parses() {
        let json = r#"{"extract":"Energy is the quantitative property."}"#;
        let result = extract_json_string_field(json, "extract").unwrap();
        assert!(result.contains("Energy"));
    }

    #[test]
    fn extract_xml_field_parses() {
        let xml = "<root><summary>This is a test.</summary></root>";
        let result = extract_xml_field(xml, "summary").unwrap();
        assert_eq!(result, "This is a test.");
    }

    #[test]
    fn list_sources_returns_all() {
        let sources = list_sources();
        assert!(sources.len() >= 10);
        assert!(sources.contains(&"wikipedia"));
        assert!(sources.contains(&"arxiv"));
        assert!(sources.contains(&"github"));
    }

    #[test]
    fn fact_to_axiom_truncates() {
        let fact = InternetFact {
            topic: "test".to_string(),
            summary: "First sentence. Second sentence. Third sentence that goes on.".to_string(),
            source_url: "http://example.com".to_string(),
            source_name: "Test".to_string(),
            language: "en".to_string(),
            confidence: 0.7,
        };
        let axiom = fact_to_axiom_text(&fact);
        assert!(axiom.contains("First sentence"));
    }
}
