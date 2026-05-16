#!/bin/bash
# Should be executed from the "client" node.

# Auto-detect number of backends from /etc/hosts
BACKEND_COUNT=$(grep -o 'backend-[0-9]\+' /etc/hosts | sort -u | wc -l)
if [ "$BACKEND_COUNT" -eq 0 ]; then BACKEND_COUNT=10; fi

echo "Stopping Backend Servers and cleaning logs ($BACKEND_COUNT nodes)..."
for i in $(seq 1 "$BACKEND_COUNT"); do
    ssh -o StrictHostKeyChecking=no "backend-$i" "pkill -f backend-binary; rm -f /tmp/backend.log" 2>/dev/null
done
echo "  -> Backends stopped."

echo "Stopping Load Balancers and cleaning logs..."
ssh -o StrictHostKeyChecking=no lb-prequal "pkill -f lb-binary; rm -f /tmp/lb.log" 2>/dev/null
ssh -o StrictHostKeyChecking=no lb-rr "pkill -f lb-binary; rm -f /tmp/lb.log" 2>/dev/null
echo "  -> Load Balancers stopped."

echo "Stopping Telemetry and wiping old metrics data..."
ssh -o StrictHostKeyChecking=no telemetry "cd /local/repository && docker compose -f docker-compose.telemetry.yml down -v" 2>/dev/null
echo "  -> Telemetry stopped."

echo "Cleaning up local test result logs..."
rm -f /tmp/prequal_*.txt /tmp/rr_*.txt

echo "Cluster teardown complete! The environment is clean and ready for ./start_cluster.sh."