#!/bin/bash

echo "Detecting cluster size..."
BACKENDS=$(grep -o 'backend-[0-9]\+' /etc/hosts | sort -u -V)

echo "1. Syncing /local/repository across the cluster..."
for node in telemetry lb-prequal lb-rr $BACKENDS; do
    echo "   -> Syncing to $node"
    # Sync everything except the binaries and .git
    rsync -avz --exclude='.git' --exclude='lb-binary' --exclude='backend/backend-binary' /local/repository/ ${node}:/local/repository/ > /dev/null
done

echo "2. Rebuilding components on Load Balancers..."
for lb in lb-prequal lb-rr; do
    echo "   -> Rebuilding on $lb"
    ssh -o StrictHostKeyChecking=no $lb "cd /local/repository && /usr/local/go/bin/go build -o lb-binary ./cmd/server"
done

echo "3. Rebuilding Backend Servers..."
for backend in $BACKENDS; do
    echo "   -> Rebuilding on $backend"
    ssh -o StrictHostKeyChecking=no $backend "cd /local/repository/backend && /usr/local/go/bin/go build -o backend-binary main.go"
done

echo "Sync and deployment complete!"
echo "If your changes require restarting running instances, remember to run:"
echo "  ./stop_cluster.sh"
echo "  ./start_cluster.sh"

