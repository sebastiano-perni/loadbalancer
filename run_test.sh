#!/bin/bash
# Compare Prequal against a second load balancing algorithm.
# Run from the "client" node after start_cluster.sh or start_cluster_full.sh.

set -e

PREQUAL_HOST="${PREQUAL_HOST:-lb-prequal:8080}"
SECOND_HOST="${SECOND_HOST:-lb-rr:8080}"
SECOND_NAME="${SECOND_NAME:-other}"
WORK="${WORK:-2500}"
WORKERS="${WORKERS:-50}"
DURATION="${DURATION:-120}"
COOLDOWN="${COOLDOWN:-10}"
CALIB_DURATION="${CALIB_DURATION:-30}"
BASELINE="${BASELINE:-}"
LEVELS_DEFAULT="0.75 0.83 0.93 1.03 1.14 1.27 1.41 1.57 1.74"
LEVELS_STR="${LEVELS:-$LEVELS_DEFAULT}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp}"

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Compare Prequal vs another load balancing algorithm by ramping load
through a set of levels (relative to a measured baseline capacity).
At each level, half the duration is spent on each load balancer; the
order is swapped between levels to mitigate ordering bias.

OPTIONS:
  -d, --duration SEC         Seconds per load level, split half/half (default: ${DURATION})
  -w, --work N               Backend work parameter (default: ${WORK})
  -c, --workers N            Concurrent clients per phase (default: ${WORKERS})
      --cooldown SEC         Cooldown between phases / levels (default: ${COOLDOWN})
      --levels "a b c..."    Load multipliers vs baseline (default: "${LEVELS_DEFAULT}")
      --prequal-host H:P     Prequal LB host:port (default: ${PREQUAL_HOST})
      --second-host H:P      Second LB host:port (default: ${SECOND_HOST})
      --second-name NAME     Label for the second algorithm (default: ${SECOND_NAME})
      --calib-duration SEC   Calibration duration (default: ${CALIB_DURATION})
      --baseline N           Skip calibration and use this baseline req/sec
      --output-dir DIR       Where to write hey output files (default: ${OUTPUT_DIR})
  -h, --help                 Show this help

ENV: every flag has a matching uppercase env var (DURATION, WORK, ...).
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--duration)      DURATION="$2";       shift 2 ;;
        -w|--work)          WORK="$2";           shift 2 ;;
        -c|--workers)       WORKERS="$2";        shift 2 ;;
        --cooldown)         COOLDOWN="$2";       shift 2 ;;
        --levels)           LEVELS_STR="$2";     shift 2 ;;
        --prequal-host)     PREQUAL_HOST="$2";   shift 2 ;;
        --second-host)      SECOND_HOST="$2";    shift 2 ;;
        --second-name)      SECOND_NAME="$2";    shift 2 ;;
        --calib-duration)   CALIB_DURATION="$2"; shift 2 ;;
        --baseline)         BASELINE="$2";       shift 2 ;;
        --output-dir)       OUTPUT_DIR="$2";     shift 2 ;;
        -h|--help)          print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

command -v hey >/dev/null || { echo "Error: hey not installed (go install github.com/rakyll/hey@latest)"; exit 1; }
command -v bc  >/dev/null || { echo "Error: bc not installed"; exit 1; }

check_lb() {
    local name="$1" host="$2"
    if ! curl -fsS "http://${host}/health" > /dev/null; then
        echo "Error: ${name} load balancer not responding at http://${host}/health"
        exit 1
    fi
}
check_lb "prequal"        "${PREQUAL_HOST}"
check_lb "${SECOND_NAME}" "${SECOND_HOST}"

read -ra LEVELS <<< "$LEVELS_STR"
mkdir -p "$OUTPUT_DIR"
HALF=$((DURATION / 2))

echo "==========================================="
echo "  Prequal vs ${SECOND_NAME}"
echo "==========================================="
echo "  prequal host:    ${PREQUAL_HOST}"
echo "  other host:      ${SECOND_HOST}"
echo "  work:            ${WORK}"
echo "  workers:         ${WORKERS}"
echo "  duration/level:  ${DURATION}s (${HALF}s per phase)"
echo "  cooldown:        ${COOLDOWN}s"
echo "  levels:          ${LEVELS[*]}"
echo "  output:          ${OUTPUT_DIR}"
echo "==========================================="

if [ -z "$BASELINE" ]; then
    echo "Calibrating baseline (${CALIB_DURATION}s with ${WORKERS} workers on ${SECOND_NAME})..."
    BASELINE=$(hey -z ${CALIB_DURATION}s -c ${WORKERS} \
        "http://${SECOND_HOST}?work=${WORK}" 2>&1 | awk '/Requests\/sec:/{print $2}')
    [ -z "$BASELINE" ] && { echo "Error: calibration failed"; exit 1; }
fi
echo "Baseline: ${BASELINE} req/sec"
echo

run_phase() {
    local label="$1" host="$2" qps_per_worker="$3" index="$4"
    local outfile="${OUTPUT_DIR}/${label}_${index}.txt"
    echo "--- ${label} on ${host} (${HALF}s, ${WORKERS} workers @ ${qps_per_worker} qps each) ---"
    hey -c "${WORKERS}" -z "${HALF}s" -q "${qps_per_worker}" \
        "http://${host}?work=${WORK}" > "${outfile}" 2>&1
}

for i in "${!LEVELS[@]}"; do
    level="${LEVELS[$i]}"
    pct=$(echo "$level * 100" | bc -l | awk '{printf "%d%%", $1}')
    total_qps=$(echo "$BASELINE * $level" | bc -l | awk '{printf "%.0f", $1}')
    qps_per_worker=$((total_qps / WORKERS))
    [ "$qps_per_worker" -lt 1 ] && qps_per_worker=1

    echo "==========================================="
    echo "Step $((i+1))/${#LEVELS[@]}: ${pct} (~${total_qps} req/s)"
    echo "==========================================="

    run_phase "${SECOND_NAME}" "${SECOND_HOST}"  "${qps_per_worker}" "${i}"
    sleep "${COOLDOWN}"
    run_phase "prequal"        "${PREQUAL_HOST}" "${qps_per_worker}" "${i}"

    echo
    echo "--- prequal results ---"
    grep -E "Requests/sec:|p50|p99|p99.9" "${OUTPUT_DIR}/prequal_${i}.txt" | head -5
    echo "--- ${SECOND_NAME} results ---"
    grep -E "Requests/sec:|p50|p99|p99.9" "${OUTPUT_DIR}/${SECOND_NAME}_${i}.txt" | head -5
    echo

    if [ $i -lt $((${#LEVELS[@]} - 1)) ]; then
        sleep "${COOLDOWN}"
    fi
done

echo "==========================================="
echo "         Test Complete"
echo "==========================================="
echo "Per-phase output: ${OUTPUT_DIR}/{prequal,${SECOND_NAME}}_*.txt"
echo "Compare in Grafana using the algorithm dropdown."
