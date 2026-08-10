#!/bin/bash

URL="http://54.205.20.87/health"

USERS=$1
REQUESTS_PER_USER=${2:-1}

TOTAL_REQUESTS=$((USERS * REQUESTS_PER_USER))

echo "=========================================="
echo "RetailEdge Load Test"
echo "=========================================="
echo "URL               : $URL"
echo "Concurrent Users  : $USERS"
echo "Requests/User     : $REQUESTS_PER_USER"
echo "Total Requests    : $TOTAL_REQUESTS"
echo "=========================================="

START=$(date +%s.%N)

TMP_DIR=$(mktemp -d)

run_request() {
    curl -s -o /dev/null \
        -w "%{http_code} %{time_total}\n" \
        --max-time 10 \
        "$URL"
}

export -f run_request
export URL

seq 1 "$TOTAL_REQUESTS" | \
    xargs -P "$TOTAL_REQUESTS" -I {} \
    bash -c 'run_request' > "$TMP_DIR/results.txt"

END=$(date +%s.%N)

DURATION=$(awk "BEGIN {print $END - $START}")

SUCCESS=$(awk '$1 == 200 {count++} END {print count+0}' "$TMP_DIR/results.txt")

FAILED=$(awk '$1 != 200 {count++} END {print count+0}' "$TMP_DIR/results.txt")

AVG_LATENCY=$(awk '
{
    sum += $2
}
END {
    if (NR > 0)
        printf "%.4f", sum / NR
    else
        print "0"
}' "$TMP_DIR/results.txt")

MAX_LATENCY=$(awk '
BEGIN {
    max = 0
}
{
    if ($2 > max)
        max = $2
}
END {
    printf "%.4f", max
}' "$TMP_DIR/results.txt")

RPS=$(awk "BEGIN {
    if ($DURATION > 0)
        print $TOTAL_REQUESTS / $DURATION
    else
        print 0
}")

SUCCESS_RATE=$(awk "BEGIN {
    if ($TOTAL_REQUESTS > 0)
        print ($SUCCESS / $TOTAL_REQUESTS) * 100
    else
        print 0
}")

echo
echo "=========================================="
echo "RESULTS"
echo "=========================================="
echo "Total Requests : $TOTAL_REQUESTS"
echo "Successful     : $SUCCESS"
echo "Failed         : $FAILED"
echo "Success Rate   : ${SUCCESS_RATE}%"
echo "Duration       : ${DURATION}s"
echo "Requests/sec   : $RPS"
echo "Avg Latency    : ${AVG_LATENCY}s"
echo "Max Latency    : ${MAX_LATENCY}s"
echo "=========================================="

rm -rf "$TMP_DIR"