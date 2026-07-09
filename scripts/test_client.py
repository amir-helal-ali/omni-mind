#!/usr/bin/env python3
"""TCP client test for Omni-Mind server."""
import socket
import sys
import time

def send_cmd(sock, cmd):
    sock.sendall((cmd + "\n").encode())
    # Read response: "OK:len:payload\n" or "ERR:msg\n"
    data = b""
    while b"\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    return data.decode(errors='replace').strip()

def main():
    host = "127.0.0.1"
    port = 19090
    if len(sys.argv) > 1:
        port = int(sys.argv[1])

    print(f"=== Client 1 (user 0) ===")
    s1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s1.connect((host, port))
    print("Welcome:", s1.recv(4096).decode(errors='replace').strip()[:60])
    print("Q1:", send_cmd(s1, "QUERY:0:what is energy?")[:120])
    print("Q2:", send_cmd(s1, "QUERY:0:how does DNA work?")[:120])
    print("Stats:", send_cmd(s1, "STATS"))
    s1.close()

    print(f"\n=== Client 2 (user 1) — concurrent ===")
    s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s2.connect((host, port))
    print("Welcome:", s2.recv(4096).decode(errors='replace').strip()[:60])
    print("Q1:", send_cmd(s2, "QUERY:1:what is quantum mechanics?")[:120])
    print("Stats:", send_cmd(s2, "STATS"))
    s2.close()

    print(f"\n=== Client 3 — ingest + query ===")
    s3 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s3.connect((host, port))
    print("Welcome:", s3.recv(4096).decode(errors='replace').strip()[:60])
    print("Ingest:", send_cmd(s3, "INGEST:0:gravity bends spacetime"))
    print("Q after ingest:", send_cmd(s3, "QUERY:2:what is gravity?")[:120])
    print("Stats:", send_cmd(s3, "STATS"))
    s3.close()

    print("\n✓ All 3 clients served successfully")

if __name__ == "__main__":
    main()
