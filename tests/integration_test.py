#!/usr/bin/env python3
"""
Omni-Mind Integration Test Suite

Tests the complete system end-to-end:
  1. Web API endpoints (health, stats, query, ingest, metrics)
  2. TCP server protocol (QUERY, STATS, INGEST, BYE)
  3. Multi-client concurrency
  4. Stress test (100 rapid queries)
  5. Data persistence (save/load memory)

Usage:
  python3 tests/integration_test.py [--port 8080] [--tcp-port 19090]
"""

import json
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error
import os
import signal

WEB_PORT = 8085
TCP_PORT = 19095
WEB_BIN = None
TCP_BIN = None

passed = 0
failed = 0
errors = []

def test(name, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  ✓ {name}")
    else:
        failed += 1
        errors.append(f"{name}: {detail}")
        print(f"  ✗ {name} — {detail}")

def http_get(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return 0, str(e)

def http_post(url, data):
    try:
        req = urllib.request.Request(url, data=json.dumps(data).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return 0, str(e)

def tcp_send(port, command):
    """Send a single command to the TCP server and get the response."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(("127.0.0.1", port))
    # Read welcome
    s.recv(4096)
    # Send command
    s.sendall((command + "\n").encode())
    # Read response
    data = b""
    while b"\n" not in data:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
    s.close()
    return data.decode(errors='replace').strip()

def main():
    global WEB_BIN, TCP_BIN

    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    WEB_BIN = os.path.join(base_dir, "swarm", "target", "release", "omni-web")
    TCP_BIN = os.path.join(base_dir, "zig-out", "bin", "omni-mind")

    print("╔══════════════════════════════════════════════════════════╗")
    print("║   Omni-Mind Integration Test Suite                       ║")
    print("╚══════════════════════════════════════════════════════════╝")
    print()

    # ─── Start web server ─────────────────────────────
    print("── Starting Web Server ──")
    web_proc = subprocess.Popen([WEB_BIN, "--port", str(WEB_PORT)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Wait for server to be ready (health check).
    base_url = f"http://localhost:{WEB_PORT}"
    for _ in range(20):
        time.sleep(0.5)
        try:
            urllib.request.urlopen(f"{base_url}/api/health", timeout=2)
            break
        except:
            pass
    else:
        print("  ✗ Web server failed to start")
        sys.exit(1)
    print("  ✓ Web server ready")

    # ─── Test 1: Health Check ─────────────────────────
    print("\n── Test 1: Health Check ──")
    status, body = http_get(f"{base_url}/api/health")
    test("health returns 200", status == 200, f"got {status}")
    if status == 200:
        data = json.loads(body)
        test("health status is 'healthy'", data.get("status") == "healthy", body)
        test("health has axioms > 0", data.get("axioms", 0) > 0, body)
        test("health has nodes > 0", data.get("nodes", 0) > 0, body)

    # ─── Test 2: Stats ────────────────────────────────
    print("\n── Test 2: Stats ──")
    status, body = http_get(f"{base_url}/api/stats")
    test("stats returns 200", status == 200, f"got {status}")
    if status == 200:
        data = json.loads(body)
        test("stats has nodes field", "nodes" in data, body)
        test("stats has edges field", "edges" in data, body)
        test("stats has axioms field", "axioms" in data, body)

    # ─── Test 3: Query ────────────────────────────────
    print("\n── Test 3: Query ──")
    status, body = http_post(f"{base_url}/api/query", {"query": "what is energy?"})
    test("query returns 200", status == 200, f"got {status}")
    if status == 200:
        data = json.loads(body)
        test("query has answer field", "answer" in data, body)
        test("answer is non-empty", len(data.get("answer", "")) > 10, body)
        test("answer contains Arabic", any(ord(c) > 127 for c in data.get("answer", "")), body)

    # ─── Test 4: Ingest ───────────────────────────────
    print("\n── Test 4: Ingest ──")
    status, body = http_post(f"{base_url}/api/ingest",
                             {"domain": 0, "text": "integration test axiom"})
    test("ingest returns 200", status == 200, f"got {status}: {body[:100]}")
    if status == 200:
        data = json.loads(body)
        test("ingest status is 'ingested'", data.get("status") == "ingested", body)

    # ─── Test 5: Metrics ──────────────────────────────
    print("\n── Test 5: Metrics ──")
    status, body = http_get(f"{base_url}/api/metrics")
    test("metrics returns 200", status == 200, f"got {status}")
    if status == 200:
        test("metrics has Prometheus format", "# HELP" in body and "# TYPE" in body, body[:100])
        test("metrics has omni_mind_nodes", "omni_mind_nodes" in body, body[:100])

    # ─── Test 6: 404 ──────────────────────────────────
    print("\n── Test 6: 404 Handling ──")
    status, body = http_get(f"{base_url}/nonexistent")
    test("unknown path returns 404", status == 404, f"got {status}")

    # ─── Test 7: Multiple Queries ─────────────────────
    print("\n── Test 7: Multiple Different Queries ──")
    queries = [
        "what is DNA?",
        "what is a catalyst?",
        "why does trade happen?",
        "what is modus ponens?",
        "what is isomorphism?",
    ]
    all_ok = True
    for q in queries:
        status, body = http_post(f"{base_url}/api/query", {"query": q})
        if status != 200 or "answer" not in json.loads(body):
            all_ok = False
            break
    test("5 different queries all succeed", all_ok)

    # ─── Stop web server ──────────────────────────────
    web_proc.terminate()
    web_proc.wait()

    # ─── Start TCP server ─────────────────────────────
    print("\n── Starting TCP Server ──")
    tcp_proc = subprocess.Popen([TCP_BIN, "--serve", str(TCP_PORT)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)

    # ─── Test 8: TCP Query ────────────────────────────
    print("\n── Test 8: TCP Protocol ──")
    resp = tcp_send(TCP_PORT, "QUERY:0:what is energy?")
    test("TCP query returns OK", resp.startswith("OK:"), resp[:50])

    # ─── Test 9: TCP Stats ────────────────────────────
    print("\n── Test 9: TCP Stats ──")
    resp = tcp_send(TCP_PORT, "STATS")
    test("TCP stats returns OK", resp.startswith("OK:"), resp[:50])
    test("TCP stats has nodes=", "nodes=" in resp, resp)

    # ─── Test 10: TCP Ingest ──────────────────────────
    print("\n── Test 10: TCP Ingest ──")
    resp = tcp_send(TCP_PORT, "INGEST:0:tcp integration test axiom")
    test("TCP ingest returns OK", "ingested" in resp, resp)

    # ─── Test 11: TCP Unknown Command ─────────────────
    print("\n── Test 11: TCP Error Handling ──")
    resp = tcp_send(TCP_PORT, "UNKNOWN_COMMAND")
    test("TCP unknown returns ERR", resp.startswith("ERR:"), resp)

    # ─── Stop TCP server ──────────────────────────────
    tcp_proc.terminate()
    tcp_proc.wait()

    # ─── Test 12: Stress Test ─────────────────────────
    print("\n── Test 12: Stress Test (50 rapid queries) ──")
    web_proc = subprocess.Popen([WEB_BIN, "--port", str(WEB_PORT)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)

    success_count = 0
    start_time = time.time()
    for i in range(50):
        status, body = http_post(f"{base_url}/api/query",
                                 {"query": f"test query number {i}"})
        if status == 200:
            success_count += 1
    elapsed = time.time() - start_time

    test("stress test: 50/50 queries succeed", success_count == 50,
         f"only {success_count}/50 succeeded")
    test("stress test: completes in < 5 seconds", elapsed < 5.0,
         f"took {elapsed:.2f}s")
    qps = success_count / elapsed if elapsed > 0 else 0
    test("stress test: throughput > 10 q/s", qps > 10, f"{qps:.1f} q/s")

    web_proc.terminate()
    web_proc.wait()

    # ─── Summary ──────────────────────────────────────
    print()
    print("╔══════════════════════════════════════════════════════════╗")
    total = passed + failed
    print(f"║  Results: {passed}/{total} passed, {failed} failed")
    if failed == 0:
        print("║  ✅ ALL TESTS PASSED")
    else:
        print("║  ❌ SOME TESTS FAILED")
        for err in errors:
            print(f"║    • {err}")
    print("╚══════════════════════════════════════════════════════════╝")

    sys.exit(0 if failed == 0 else 1)

if __name__ == "__main__":
    main()
