#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
RATES=(1000 2000 4000 8000 16000 32000)    # requests/sec to sweep
DURATION="60s"
WORKER_COUNT=50                            # fixed — isolate rate as the variable
TARGET_COUNT=5000                          # pool of distinct random payloads
URL="http://localhost:4000/jobs"
STATS_URL="http://localhost:4000/stats"
OUT_DIR="vegeta_results"
SUMMARY_CSV="$OUT_DIR/summary.csv"
POLL_INTERVAL=1                            # seconds, for both /stats and docker stats

mkdir -p "$OUT_DIR"

# ------------------------------------------------------------
# Summary CSV header
# ------------------------------------------------------------
cat > "$SUMMARY_CSV" <<EOF
rate_requested,rate_achieved,success_pct,status_codes,p50_ms,p95_ms,p99_ms,max_ms,jobs_completed,throughput_stats,peak_queue,queued_jobs_end,busy_workers_end,idle_workers_end,dlq_jobs,cpu_avg_pct,mem_avg_mb,mem_peak_mb
EOF

# ------------------------------------------------------------
# Generate a pool of vegeta targets with random JSON payloads
# ------------------------------------------------------------
generate_targets() {
    # vegeta's plain-text target format only supports bodies via @file references,
    # not inline bodies. Since each request needs a different random payload, we use
    # vegeta's JSON target format instead — one JSON object per line, body base64-encoded.
    local file="$1"
    local count="$2"
    : > "$file"
    for ((i = 0; i < count; i++)); do
        payload=$(printf '%06x%06x' $RANDOM $RANDOM)
        local body="{\"payload\": \"${payload}\"}"
        local body_b64
        body_b64=$(printf '%s' "$body" | base64 -w0)
        printf '{"method":"POST","url":"%s","header":{"Content-Type":["application/json"]},"body":"%s"}\n' \
            "$URL" "$body_b64" >> "$file"
    done
}

# ------------------------------------------------------------
# Background pollers
# ------------------------------------------------------------
poll_docker_stats() {
    local outfile="$1"
    : > "$outfile"
    while true; do
        docker stats eljobs --no-stream --format '{{.CPUPerc}},{{.MemUsage}}' \
            | sed 's/%//; s/ \/ .*MiB/,/; s/MiB//' \
            >> "$outfile" 2>/dev/null || true
        sleep "$POLL_INTERVAL"
    done
}

poll_app_stats() {
    # timeseries: epoch_seconds,queued_jobs,busy_workers,idle_workers,throughput,peak_queue,dlq_jobs
    local outfile="$1"
    : > "$outfile"
    while true; do
        local s
        s=$(curl -s "$STATS_URL" || echo '{}')
        local ts queued busy idle thr peak dlq
        ts=$(date +%s)
        queued=$(get_stat "$s" queued_jobs)
        busy=$(get_stat "$s" busy_workers)
        idle=$(get_stat "$s" idle_workers)
        thr=$(get_stat "$s" throughput)
        peak=$(get_stat "$s" peak_queue)
        dlq=$(get_stat "$s" dlq_jobs)
        echo "$ts,$queued,$busy,$idle,$thr,$peak,$dlq" >> "$outfile"
        sleep "$POLL_INTERVAL"
    done
}

get_stat() {
    echo "$1" | grep -o "\"$2\":[0-9.]*" | cut -d: -f2
}

aggregate_docker_stats() {
    local file="$1"
    CPU_AVG=$(awk -F',' '{s+=$1;n++} END{if(n) printf "%.2f",s/n; else print 0}' "$file")
    MEM_AVG=$(awk -F',' '{s+=$2;n++} END{if(n) printf "%.2f",s/n; else print 0}' "$file")
    MEM_PEAK=$(awk -F',' '{if($2>m)m=$2} END{printf "%.2f",m}' "$file")
}

# ------------------------------------------------------------
# Single rate run
# ------------------------------------------------------------
run_rate() {
    local rate="$1"
    echo ""
    echo "===================================================="
    echo "Rate: ${rate} req/s | Duration: $DURATION | Workers: $WORKER_COUNT"
    echo "===================================================="

    export WORKER_COUNT
    docker compose down >/dev/null 2>&1 || true
    docker compose up -d --wait
    sleep 2

    local targets_file="$OUT_DIR/targets.txt"
    generate_targets "$targets_file" "$TARGET_COUNT"

    local docker_stats_file appstats_file vegeta_bin vegeta_json
    docker_stats_file=$(mktemp)
    appstats_file="$OUT_DIR/timeseries_rate${rate}.csv"
    echo "epoch,queued_jobs,busy_workers,idle_workers,throughput,peak_queue,dlq_jobs" > "$appstats_file"
    vegeta_bin="$OUT_DIR/vegeta_rate${rate}.bin"
    vegeta_json="$OUT_DIR/vegeta_rate${rate}.json"

    poll_docker_stats "$docker_stats_file" &
    local docker_poll_pid=$!
    poll_app_stats "$appstats_file.tmp" &
    local app_poll_pid=$!

    # vegeta attack: fixed rate, closed pool of targets cycled sequentially
    vegeta attack \
        -targets="$targets_file" \
        -format=json \
        -rate="${rate}/1s" \
        -duration="$DURATION" \
        -timeout=30s \
        > "$vegeta_bin"

    kill "$docker_poll_pid" "$app_poll_pid" 2>/dev/null || true
    wait "$docker_poll_pid" "$app_poll_pid" 2>/dev/null || true

    # merge tmp timeseries (header already written) — poll_app_stats writes raw rows
    cat "$appstats_file.tmp" >> "$appstats_file"
    rm -f "$appstats_file.tmp"

    aggregate_docker_stats "$docker_stats_file"
    rm -f "$docker_stats_file"

    vegeta report -type=json "$vegeta_bin" > "$vegeta_json"

    local rate_achieved success p50 p95 p99 vmax status_codes
    rate_achieved=$(get_stat "$(cat "$vegeta_json")" rate)
    success=$(get_stat "$(cat "$vegeta_json")" success)
    p50=$(python3 -c "import json;d=json.load(open('$vegeta_json'));print(round(d['latencies']['50th']/1e6,2))" 2>/dev/null || echo "NA")
    p95=$(python3 -c "import json;d=json.load(open('$vegeta_json'));print(round(d['latencies']['95th']/1e6,2))" 2>/dev/null || echo "NA")
    p99=$(python3 -c "import json;d=json.load(open('$vegeta_json'));print(round(d['latencies']['99th']/1e6,2))" 2>/dev/null || echo "NA")
    vmax=$(python3 -c "import json;d=json.load(open('$vegeta_json'));print(round(d['latencies']['max']/1e6,2))" 2>/dev/null || echo "NA")
    status_codes=$(python3 -c "import json;d=json.load(open('$vegeta_json'));print(';'.join(f'{k}:{v}' for k,v in d['status_codes'].items()))" 2>/dev/null || echo "NA")
    success_pct=$(python3 -c "print(round(${success:-0}*100,2))" 2>/dev/null || echo "NA")

    local final_stats jobs_completed throughput peak_queue queued busy idle dlq
    final_stats=$(curl -s "$STATS_URL")
    jobs_completed=$(get_stat "$final_stats" jobs_completed)
    throughput=$(get_stat "$final_stats" throughput)
    peak_queue=$(get_stat "$final_stats" peak_queue)
    queued=$(get_stat "$final_stats" queued_jobs)
    busy=$(get_stat "$final_stats" busy_workers)
    idle=$(get_stat "$final_stats" idle_workers)
    dlq=$(get_stat "$final_stats" dlq_jobs)

    echo "$rate,$rate_achieved,$success_pct,\"$status_codes\",$p50,$p95,$p99,$vmax,$jobs_completed,$throughput,$peak_queue,$queued,$busy,$idle,$dlq,$CPU_AVG,$MEM_AVG,$MEM_PEAK" \
        >> "$SUMMARY_CSV"

    echo "Achieved rate:  $rate_achieved req/s"
    echo "Success:        ${success_pct}%"
    echo "Jobs completed: $jobs_completed"
    echo "Queue at end:   $queued (peak: $peak_queue)"
    echo "DLQ:            $dlq"
    echo "Timeseries:     $appstats_file"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
for r in "${RATES[@]}"; do
    run_rate "$r"
done

docker compose down

echo ""
echo "Done. Summary: $SUMMARY_CSV"
echo "Per-rate timeseries in $OUT_DIR/timeseries_rate*.csv"
