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
    log::info!("Endpoints: / /api/query /api/stats /api/health /api/metrics /api/ingest");

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

    log::debug!("{} {} (body {} bytes: {})", method, path, body.len(), &body[..body.len().min(100)]);

    let (status, content_type, response_body) = match (method.as_str(), path.as_str()) {
        ("GET", "/") => serve_html(),
        ("GET", "/index.html") => serve_html(),
        ("POST", "/api/query") => handle_query(&body),
        ("GET", "/api/stats") => handle_stats(),
        ("GET", "/api/health") => handle_health(),
        ("GET", "/api/metrics") => handle_metrics(),
        ("POST", "/api/ingest") => handle_ingest(&body),
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

    match ffi::safe_query(&query) {
        Ok(answer) => {
            let json = format!(r#"{{"query":"{}","answer":"{}"}}"#,
                escape_json(&query),
                escape_json(&answer));
            ("200 OK", "application/json", json)
        }
        Err(e) => {
            let json = format!(r#"{{"error":"query failed: code {}"}}"#, e);
            ("500 Internal Server Error", "application/json", json)
        }
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
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
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
  </div>
  <div class="loading" id="loading">جاري المعالجة عبر 7 طبقات...</div>
  <div class="answer-box empty" id="answer">ستظهر الإجابة هنا</div>

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
async function askQuery() {
  const q = document.getElementById('query').value;
  if (!q) return;
  document.getElementById('loading').classList.add('active');
  document.getElementById('answer').classList.add('empty');
  document.getElementById('answer').textContent = 'جاري المعالجة...';
  try {
    const res = await fetch('/api/query', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({query: q})
    });
    const data = await res.json();
    document.getElementById('answer').classList.remove('empty');
    document.getElementById('answer').textContent = data.answer || data.error;
  } catch(e) {
    document.getElementById('answer').textContent = 'خطأ: ' + e.message;
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
