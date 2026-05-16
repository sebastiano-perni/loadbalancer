#!/bin/bash

set -eo pipefail

echo "Detecting cluster size..."
BACKENDS=$(grep -o 'backend-[0-9]\+' /etc/hosts | sort -u -V || true)

if [ -z "$BACKENDS" ]; then
    echo "Warning: No backend nodes detected in /etc/hosts (Found: $BACKENDS)"
fi

ALL_NODES="client telemetry lb-prequal lb-rr $BACKENDS"

echo "1. Setting up all nodes in parallel..."

declare -A PIDS

for node in $ALL_NODES; do
    echo "   -> Starting setup on $node (Logs saved to setup_${node}.log)"
    ssh -o StrictHostKeyChecking=no $node "cd /local/repository && ./cloudlab_setup.sh" > "setup_${node}.log" 2>&1 &
    PIDS[$node]=$!
done

echo "Waiting for all setup tasks to complete (this may take a few minutes)..."

# Wait for each job and check its exit code
FAILED=0
for node in "${!PIDS[@]}"; do
    if wait ${PIDS[$node]}; then
        echo "   [OK] Setup succeeded on $node!"
    else
        echo "   [ERROR] Setup failed on $node! Check setup_${node}.log for details."
        FAILED=1
    fi
done

if [ $FAILED -ne 0 ]; then
    echo "Fatal: One or more nodes failed during setup. Aborting."
    exit 1
fi

echo "2. Running health checks on all nodes..."
HEALTH_FAILED=0

HEALTH_CHECK_CMD="
    export PATH=\$PATH:/usr/local/go/bin;
    command -v go >/dev/null 2>&1 || { echo 'Go missing'; exit 1; };
    command -v docker >/dev/null 2>&1 || { echo 'Docker missing'; exit 1; };
    [ -f /local/repository/lb-binary ] || { echo 'LB binary missing'; exit 1; };
    [ -f /local/repository/backend/backend-binary ] || { echo 'Backend binary missing'; exit 1; };
    exit 0
"

for node in $ALL_NODES; do
    if ssh -o StrictHostKeyChecking=no $node "$HEALTH_CHECK_CMD"; then
        echo "   [OK] Validation passed on $node!"
    else
        echo "   [ERROR] Health check failed on $node! Binaries or tools are missing."
        HEALTH_FAILED=1
    fi
done

if [ $HEALTH_FAILED -ne 0 ]; then
    echo "Fatal: Health checks failed! Please inspect the nodes manually."
    exit 1
fi

echo "All setups and health checks passed. Setup complete!"