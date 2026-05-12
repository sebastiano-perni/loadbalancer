#!/bin/bash
# stop_cluster.sh
# Should be executed from the "client" node.

echo "Stopping Backend Servers and cleaning logs..."
for i in {1..13}; do
    ssh -o StrictHostKeyChecking=no backend-$i "pkill -f backend-binary; rm -f /tmp/backend.log" 2>/dev/null
done
echo "  -> Backends stopped."

echo "Stopping Load Balancers and cleaning logs..."
ssh -o StrictHostKeyChecking=no lb-prequal "pkill -f lb-binary; rm -f /tmp/lb.log" 2>/dev/null
ssh -o StrictHostKeyChecking=no lb-rr "pkill -f lb-binary; rm -f /tmp/lb.log" 2>/dev/null
echo "  -> Load Balancers stopped."

echo "Stopping Telemetry and wiping old metrics data..."
ssh -o StrictHostKeyChecking=no telemetry "cd /local/repository && docker compose down -v" 2>/dev/null
echo "  -> Telemetry stopped."

echo "Cleaning up local test result logs..."
rm -f /tmp/prequal_*.txt /tmp/rr_*.txt

echo "Cluster teardown complete! The environment is clean and ready for ./start_cluster.sh."