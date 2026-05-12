#!/bin/bash
# start_cluster.sh
# Should be executed from the "client" node.

echo "Cleaning up any existing processes across the cluster..."
for i in {1..13}; do ssh -o StrictHostKeyChecking=no backend-$i "pkill -f backend-binary" 2>/dev/null; done
ssh -o StrictHostKeyChecking=no lb-prequal "pkill -f lb-binary" 2>/dev/null
ssh -o StrictHostKeyChecking=no lb-rr "pkill -f lb-binary" 2>/dev/null

echo "Starting Telemetry (Prometheus & Grafana)..."
ssh -o StrictHostKeyChecking=no telemetry "cd /local/repository && docker compose up -d prometheus grafana"

echo "Starting Backend Servers..."
# Simulate antagonists on the first 3 backends
for i in {1..3}; do
    echo "  -> Starting backend-$i (Contended: CPU_LOAD=60)"
    ssh -o StrictHostKeyChecking=no backend-$i "cd /local/repository/backend && PORT=80 CPU_LOAD=60 nohup ./backend-binary > /tmp/backend.log 2>&1 &"
done

# Start the remaining 10 backends as clean servers
for i in {4..13}; do
    echo "  -> Starting backend-$i (Clean: CPU_LOAD=0)"
    ssh -o StrictHostKeyChecking=no backend-$i "cd /local/repository/backend && PORT=80 CPU_LOAD=0 nohup ./backend-binary > /tmp/backend.log 2>&1 &"
done

echo "Starting Load Balancers..."
# Generate the comma-separated string: backend-1:80,backend-2:80,...backend-13:80
BACKENDS=$(for i in {1..13}; do echo -n "backend-${i}:80,"; done | sed 's/,$//')

# Start Prequal
ssh -o StrictHostKeyChecking=no lb-prequal "cd /local/repository && BACKEND_SERVERS=$BACKENDS LB_ALGORITHM=prequal nohup ./lb-binary > /tmp/lb.log 2>&1 &"

# Start Round-Robin
ssh -o StrictHostKeyChecking=no lb-rr "cd /local/repository && BACKEND_SERVERS=$BACKENDS LB_ALGORITHM=roundrobin nohup ./lb-binary > /tmp/lb.log 2>&1 &"

echo "Cluster started successfully! Give it 10-15 seconds to stabilize before running the test."