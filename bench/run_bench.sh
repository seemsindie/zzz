#!/usr/bin/env bash
set -euo pipefail

# ── Configuration (override via env vars) ──────────────────────────────
DURATION="${BENCH_DURATION:-10s}"
THREADS="${BENCH_THREADS:-4}"
CONNECTIONS="${BENCH_CONNECTIONS:-100}"
HOST="${BENCH_HOST:-http://127.0.0.1:3000}"
MAX_WAIT=10  # seconds to wait for server

# ── Detect benchmark tool ──────────────────────────────────────────────
BENCH_TOOL=""
if command -v wrk &>/dev/null; then
    BENCH_TOOL="wrk"
elif command -v hey &>/dev/null; then
    BENCH_TOOL="hey"
else
    echo "ERROR: Neither 'wrk' nor 'hey' found."
    echo ""
    echo "Install one of:"
    echo "  brew install wrk       # macOS"
    echo "  brew install hey       # macOS"
    echo "  go install github.com/rakyll/hey@latest  # Go"
    exit 1
fi

echo "Using benchmark tool: $BENCH_TOOL"
echo "Duration: $DURATION | Threads: $THREADS | Connections: $CONNECTIONS"
echo ""

# ── Build and start bench server ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Building benchmark server (ReleaseFast)..."
cd "$PROJECT_DIR"
zig build bench 2>&1

echo "Starting benchmark server on port 3000..."
./zig-out/bin/zzz-bench &
SERVER_PID=$!

# Ensure cleanup on exit
cleanup() {
    if kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f /tmp/zzz-bench.db /tmp/zzz-bench.db-wal /tmp/zzz-bench.db-shm
}
trap cleanup EXIT

# ── Wait for server ready ──────────────────────────────────────────────
echo "Waiting for server..."
elapsed=0
while ! curl -s -o /dev/null "$HOST/plaintext" 2>/dev/null; do
    sleep 0.5
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge "$((MAX_WAIT * 2))" ]; then
        echo "ERROR: Server did not start within ${MAX_WAIT}s"
        exit 1
    fi
done
echo "Server ready."
echo ""

# ── Run benchmarks ─────────────────────────────────────────────────────
run_bench() {
    local name="$1"
    local path="$2"

    echo "═══════════════════════════════════════════════════════════════"
    echo "  $name — $HOST$path"
    echo "═══════════════════════════════════════════════════════════════"

    if [ "$BENCH_TOOL" = "wrk" ]; then
        wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" "$HOST$path"
    else
        # hey uses -z for duration, -c for concurrency
        hey -z "$DURATION" -c "$CONNECTIONS" "$HOST$path"
    fi
    echo ""
}

run_bench "Plaintext (text/plain)" "/plaintext"
run_bench "JSON (application/json)" "/json"
run_bench "Path Params (routing overhead)" "/users/42"
run_bench "DB Read (SQLite PK lookup)" "/db"
run_bench "DB Insert (SQLite INSERT)" "/db-insert"

echo "═══════════════════════════════════════════════════════════════"
echo "  HTTP benchmark complete."
echo "═══════════════════════════════════════════════════════════════"

# ── SQLite benchmark (no wrk/hey needed) ──────────────────────────────
echo ""
echo "Running SQLite benchmark..."
./zig-out/bin/zzz-bench-sqlite

echo "═══════════════════════════════════════════════════════════════"
echo "  All benchmarks complete."
echo "═══════════════════════════════════════════════════════════════"
