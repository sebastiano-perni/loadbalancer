#!/bin/bash
# start_cluster.sh
# Should be executed from the "client" node.

# Auto-detect number of backends from /etc/hosts
BACKEND_COUNT=$(grep -o 'backend-[0-9]\+' /etc/hosts | sort -u | wc -l)
if [ "$BACKEND_COUNT" -eq 0 ]; then BACKEND_COUNT=13; fi
echo "Detected $BACKEND_COUNT backend nodes."

echo "Cleaning up any existing processes across the cluster..."
for i in $(seq 1 $BACKEND_COUNT); do ssh -o StrictHostKeyChecking=no backend-$i "pkill -f backend-binary" 2>/dev/null; done
ssh -o StrictHostKeyChecking=no lb-prequal "pkill -f lb-binary" 2>/dev/null
ssh -o StrictHostKeyChecking=no lb-rr "pkill -f lb-binary" 2>/dev/null

echo "Starting Telemetry (Prometheus & Grafana)..."
ssh -o StrictHostKeyChecking=no telemetry "cd /local/repository && docker compose -f docker-compose.telemetry.yml up -d"

echo "Starting Backend Servers..."
# Simulate antagonists on up to the first 3 backends
CONTENDED_COUNT=3
if [ "$BACKEND_COUNT" -lt 3 ]; then CONTENDED_COUNT=$BACKEND_COUNT; fi

for i in $(seq 1 $CONTENDED_COUNT); do
    echo "  -> Starting backend-$i (Contended: CPU_LOAD=60)"
    ssh -o StrictHostKeyChecking=no backend-$i "cd /local/repository/backend && GOMAXPROCS=1 PORT=80 CPU_LOAD=60 SERVER_ID=backend-$i nohup ./backend-binary > /tmp/backend.log 2>&1 &"
done

# Start the remaining backends as clean servers
if [ "$BACKEND_COUNT" -gt "$CONTENDED_COUNT" ]; then
    for i in $(seq $((CONTENDED_COUNT + 1)) $BACKEND_COUNT); do
        echo "  -> Starting backend-$i (Clean: CPU_LOAD=0)"
        ssh -o StrictHostKeyChecking=no backend-$i "cd /local/repository/backend && GOMAXPROCS=1 PORT=80 CPU_LOAD=0 SERVER_ID=backend-$i nohup ./backend-binary > /tmp/backend.log 2>&1 &"
    done
fi

echo "Starting Load Balancers..."
# Generate the comma-separated string: backend-1:80,backend-2:80,...
BACKENDS=$(for i in $(seq 1 $BACKEND_COUNT); do echo -n "backend-${i}:80,"; done | sed 's/,$//')

# Start Prequal
ssh -o StrictHostKeyChecking=no lb-prequal "cd /local/repository && BACKEND_SERVERS=$BACKENDS LB_ALGORITHM=prequal nohup ./lb-binary > /tmp/lb.log 2>&1 &"

# Start Round-Robin
ssh -o StrictHostKeyChecking=no lb-rr "cd /local/repository && BACKEND_SERVERS=$BACKENDS LB_ALGORITHM=roundrobin nohup ./lb-binary > /tmp/lb.log 2>&1 &"

echo "Cluster started successfully! Give it 10-15 seconds to stabilize before running the test."