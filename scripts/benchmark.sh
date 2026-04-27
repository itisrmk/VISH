#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="$root/benchmarks"
configuration="${CONFIGURATION:-Release}"
arch="${ARCH:-arm64}"
sample_seconds="${SAMPLE_SECONDS:-5}"
settle_seconds="${SETTLE_SECONDS:-3}"
mkdir -p "$out_dir"

ms() {
  ruby -rtime -e 'puts (Time.now.to_f * 1000).round'
}

destination="platform=macOS,arch=$arch"

started="$(ms)"
xcodebuild -scheme vish -configuration "$configuration" -destination "$destination" ARCHS="$arch" ONLY_ACTIVE_ARCH=YES >/dev/null
ended="$(ms)"
build_ms=$((ended - started))

app_dir="$(
  xcodebuild -showBuildSettings -scheme vish -configuration "$configuration" -destination "$destination" ARCHS="$arch" ONLY_ACTIVE_ARCH=YES 2>/dev/null |
    awk -F ' = ' '/^[[:space:]]+BUILT_PRODUCTS_DIR = / { print $2; exit }'
)"
app_path="$app_dir/vish.app"

pkill -x vish 2>/dev/null || true
for _ in {1..100}; do
  pgrep -x vish >/dev/null || break
  sleep 0.05
done

launch_started="$(ms)"
open -n "$app_path"

pid=""
for _ in {1..100}; do
  pid="$(pgrep -n -x vish || true)"
  [[ -n "$pid" ]] && break
  sleep 0.05
done

if [[ -z "$pid" ]]; then
  echo "vish did not stay running" >&2
  exit 1
fi

launch_to_pid_ms=$(($(ms) - launch_started))
sleep "$settle_seconds"

if ! kill -0 "$pid" 2>/dev/null; then
  echo "vish exited before process metrics could be sampled" >&2
  exit 1
fi

rss_kb=0
cpu_sum="0"
sample_count=0
for _ in $(seq 1 "$sample_seconds"); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "vish exited during process metrics sampling" >&2
    exit 1
  fi
  rss_kb="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
  cpu_percent="$(ps -o %cpu= -p "$pid" 2>/dev/null | awk '{$1=$1; print}')"
  cpu_sum="$(awk -v a="$cpu_sum" -v b="${cpu_percent:-0}" 'BEGIN { print a + b }')"
  sample_count=$((sample_count + 1))
  sleep 1
done

cpu_average="$(awk -v total="$cpu_sum" -v count="$sample_count" 'BEGIN { if (count == 0) print 0; else printf "%.3f", total / count }')"
out_file="$out_dir/$(date +%F).json"

BUILD_MS="$build_ms" \
LAUNCH_TO_PID_MS="$launch_to_pid_ms" \
RSS_KB="${rss_kb:-0}" \
CPU_AVERAGE="$cpu_average" \
PID="$pid" \
APP_PATH="$app_path" \
CONFIGURATION="$configuration" \
ARCH="$arch" \
SAMPLE_SECONDS="$sample_seconds" \
SETTLE_SECONDS="$settle_seconds" \
ruby -rjson -e '
  rss = Integer(ENV.fetch("RSS_KB"))
  cpu = Float(ENV.fetch("CPU_AVERAGE"))
  data = {
    schema_version: 1,
    configuration: ENV.fetch("CONFIGURATION"),
    arch: ENV.fetch("ARCH"),
    build_ms: Integer(ENV.fetch("BUILD_MS")),
    launch_to_pid_ms: Integer(ENV.fetch("LAUNCH_TO_PID_MS")),
    idle_rss_kb: rss,
    idle_cpu_percent_average: cpu,
    sample_seconds: Integer(ENV.fetch("SAMPLE_SECONDS")),
    settle_seconds: Integer(ENV.fetch("SETTLE_SECONDS")),
    budgets: {
      idle_rss_kb: 80_000,
      idle_cpu_percent: 0.0
    },
    budget_status: {
      idle_rss: rss <= 80_000,
      idle_cpu_smoke: cpu <= 0.1
    },
    pid: Integer(ENV.fetch("PID")),
    app_path: ENV.fetch("APP_PATH"),
    note: "Smoke benchmark. Frame-level budgets come from os_signpost intervals in subsystem com.vish.app category Performance."
  }
  puts JSON.pretty_generate(data)
' >"$out_file"

cat "$out_file"
