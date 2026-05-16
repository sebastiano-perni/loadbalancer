#!/bin/bash
# Should be executed from the "client" node.

export PREQUAL_HOST="lb-prequal:8080"
export RR_HOST="lb-rr:8080"

echo "Starting Prequal vs Round-Robin Ramp Test..."
echo "Targeting $PREQUAL_HOST and $RR_HOST"

cd /local/repository || exit

# Pass any arguments to compare.sh
./compare.sh "$@"