#!/usr/bin/env python3
"""Test 3-node Omni-Mind Swarm network.

Node 1 (port 18101) ← Node 2 (port 18102) ← Node 3 (port 18103)
Each node connects to the previous one as a peer.
Tests gossip propagation of axioms.
"""
import subprocess
import time
import sys
import os

NODE_BIN = "/home/z/my-project/omni-mind/swarm/target/release/omni-swarm-node"

def start_node(port, peers=None, name="node"):
    args = [NODE_BIN, "--port", str(port)]
    if peers:
        args += ["--peers", peers]
    log_file = open(f"/tmp/swarm_{name}.log", "w")
    proc = subprocess.Popen(args, stdout=log_file, stderr=subprocess.STDOUT)
    print(f"Started {name} on port {port} (PID {proc.pid})")
    return proc

def main():
    print("=== Omni-Mind Swarm: 3-node test ===\n")

    # Start node 1 (no peers)
    n1 = start_node(18101, None, "node1")
    time.sleep(1)

    # Start node 2, peer with node 1
    n2 = start_node(18102, "127.0.0.1:18101", "node2")
    time.sleep(1)

    # Start node 3, peer with node 1 and 2
    n3 = start_node(18103, "127.0.0.1:18101,127.0.0.1:18102", "node3")
    time.sleep(3)

    print("\n=== All 3 nodes running for 5 seconds ===")
    time.sleep(5)

    # Terminate all nodes
    print("\n=== Shutting down ===")
    for proc in [n3, n2, n1]:
        proc.terminate()
        proc.wait()

    # Print logs
    for name in ["node1", "node2", "node3"]:
        print(f"\n=== {name} log ===")
        with open(f"/tmp/swarm_{name}.log") as f:
            lines = f.readlines()
            for line in lines[:12]:
                print(line.rstrip())

    # Check for gossip propagation
    print("\n=== Gossip analysis ===")
    for name in ["node1", "node2", "node3"]:
        with open(f"/tmp/swarm_{name}.log") as f:
            content = f.read()
            broadcasts = content.count("Broadcast:")
            accepted = content.count("Accepted gossip")
            msgs_sent = content.count("msgs sent")
            print(f"  {name}: {broadcasts} broadcasts, {accepted} accepted")

if __name__ == "__main__":
    main()
