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
for i in $(seq 1 "$BACKEND_COUNT"); do ssh -o StrictHostKeyChecking=no "backend-$i" "pkill -f backend-binary; pkill -f stress-ng" 2>/dev/null; done
ssh -o StrictHostKeyChecking=no lb-prequal "pkill -f lb-binary" 2>/dev/null
ssh -o StrictHostKeyChecking=no lb-rr "pkill -f lb-binary" 2>/dev/null

echo "Starting Telemetry (Prometheus & Grafana)..."
ssh -o StrictHostKeyChecking=no telemetry "cd /local/repository && docker compose -f docker-compose.telemetry.yml up -d"

echo "Starting Backend Servers..."
# Simulate antagonists on up to the first 3 backends
CONTENDED_COUNT=${CONTENDED_COUNT:-3}
STRESS_WORKERS=${STRESS_WORKERS:-2}
STRESS_LOAD=${STRESS_LOAD:-60}

if [ "$BACKEND_COUNT" -lt "$CONTENDED_COUNT" ]; then CONTENDED_COUNT=$BACKEND_COUNT; fi

for i in $(seq 1 "$CONTENDED_COUNT"); do
    echo "  -> Starting backend-$i (Contended: STRESS_WORKERS=$STRESS_WORKERS, STRESS_LOAD=$STRESS_LOAD%)"
    ssh -o StrictHostKeyChecking=no "backend-$i" "nohup stress-ng --cpu $STRESS_WORKERS --cpu-load $STRESS_LOAD > /tmp/stress.log 2>&1 & cd /local/repository/backend && GOMAXPROCS=1 PORT=80 SERVER_ID=backend-$i nohup ./backend-binary > /tmp/backend.log 2>&1 &" &
done

# Start the remaining backends as clean servers
if [ "$BACKEND_COUNT" -gt "$CONTENDED_COUNT" ]; then
    for i in $(seq $((CONTENDED_COUNT + 1)) "$BACKEND_COUNT"); do
        echo "  -> Starting backend-$i (Clean)"
        ssh -o StrictHostKeyChecking=no "backend-$i" "cd /local/repository/backend && GOMAXPROCS=1 PORT=80 SERVER_ID=backend-$i nohup ./backend-binary > /tmp/backend.log 2>&1 &" &
    done
fi

echo "Starting Load Balancers..."
# Generate the comma-separated string: backend-1:80,backend-2:80,...
BACKENDS=$(for i in $(seq 1 "$BACKEND_COUNT"); do echo -n "backend-${i}:80,"; done | sed 's/,$//')

# Start Prequal
ssh -o StrictHostKeyChecking=no lb-prequal "cd /local/repository && BACKEND_SERVERS=$BACKENDS LB_ALGORITHM=prequal nohup ./lb-binary > /tmp/lb.log 2>&1 &" &

# Start Secondary Load Balancer
ssh -o StrictHostKeyChecking=no lb-rr "cd /local/repository && BACKEND_SERVERS=$BACKENDS LB_ALGORITHM=$SECOND_LB_ALGO nohup ./lb-binary > /tmp/lb.log 2>&1 &" &

echo "Cluster started successfully! Give it 10-15 seconds to stabilize before running the test."