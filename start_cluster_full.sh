#!/bin/bash
# Should be executed from the "client" node.

SECOND_LB_ALGO=${1:-roundrobin}

# Supported algorithms (add more here in the future)
VALID_ALGOS=("roundrobin" "wrr" "random" "leastloaded")

if [[ ! " ${VALID_ALGOS[*]} " == *" $SECOND_LB_ALGO "* ]]; then
    echo "Error: Invalid load balancing algorithm '$SECOND_LB_ALGO'."
    echo "Supported algorithms are: ${VALID_ALGOS[*]}"
    exit 1
fi

# Auto-detect number of backends from /etc/hosts
BACKEND_COUNT=$(grep -o 'backend-[0-9]\+' /etc/hosts | sort -u | wc -l)
if [ "$BACKEND_COUNT" -eq 0 ]; then BACKEND_COUNT=10; fi
echo "Detected $BACKEND_COUNT backend nodes."

echo "Cleaning up any existing processes across the cluster..."
for i in $(seq 1 "$BACKEND_COUNT"); do ssh -o StrictHostKeyChecking=no "backend-$i" "pkill -f backend-binary; pkill -f cpulimit" 2>/dev/null; done
ssh -o StrictHostKeyChecking=no lb-prequal "pkill -f lb-binary" 2>/dev/null
ssh -o StrictHostKeyChecking=no lb-rr "pkill -f lb-binary" 2>/dev/null

echo "Starting Telemetry (Prometheus & Grafana)..."
ssh -o StrictHostKeyChecking=no telemetry "cd /local/repository && docker compose -f docker-compose.telemetry.yml up -d"

echo "Starting Backend Servers..."
# 10 processes per physical backend, with NO antagonist servers.
# CPU limit 10% per process.

for i in $(seq 1 "$BACKEND_COUNT"); do
    echo "  -> Starting 10 instances on backend-$i (Clean, 10% CPU limit)"
    # Start 10 backends on ports 8000-8009
    ssh -o StrictHostKeyChecking=no "backend-$i" "cd /local/repository/backend && for p in \$(seq 8000 8009); do PORT=$p SERVER_ID=backend-$i-$p nohup cpulimit -l 10 -- ./backend-binary > /tmp/backend_$p.log 2>&1 &" &
done

echo "Starting Load Balancers..."
# Generate the comma-separated string for all 100 backends
BACKENDS=""
for i in $(seq 1 "$BACKEND_COUNT"); do
    for p in $(seq 8000 8009); do
        BACKENDS="${BACKENDS}backend-${i}:${p},"
    done
done
BACKENDS=$(echo "$BACKENDS" | sed 's/,$//')

# Start Prequal
ssh -o StrictHostKeyChecking=no lb-prequal "cd /local/repository && BACKEND_SERVERS=$BACKENDS LB_ALGORITHM=prequal nohup ./lb-binary > /tmp/lb.log 2>&1 &" &

# Start Secondary Load Balancer
ssh -o StrictHostKeyChecking=no lb-rr "cd /local/repository && BACKEND_SERVERS=$BACKENDS LB_ALGORITHM=$SECOND_LB_ALGO nohup ./lb-binary > /tmp/lb.log 2>&1 &" &

echo "Cluster started successfully! Give it 10-15 seconds to stabilize before running the test."
