#!/usr/bin/env bash
# pi-plugin-benchmark: measure pi startup cost with package subsets.
#
# Usage:
#   bench.sh [--cold] [--runs N] [package ...]
#
#   --cold       Wipe the jiti cache (/tmp/jiti) before each variant's first
#                run and measure single cold runs. The cache regenerates.
#   --runs N     Warm runs per variant (default 2). Cold mode ignores this.
#   package ...  npm package names. Default: every package in the real
#                ~/.pi/agent/settings.json.
#
# Variants measured:
#   1. baseline  — no packages (pi + node floor)
#   2. one per package — single package enabled (includes one-time shared
#      costs, so deltas are not additive; the inequality is still informative)
#
# Method (verified 2026-09, see ~/.pi/agent/skills/pi-plugin-benchmark/SKILL.md):
#   - `pi --help` loads all configured packages and is a faithful startup proxy.
#   - PI_OFFLINE=1 keeps update checks out of the measurement.
#   - A sandbox agent dir (persistent copy of the real npm dir) keeps the real
#     install untouched; only the sandbox settings.json changes per variant.
set -euo pipefail

REAL_NPM="${PI_PACKAGE_DIR:-$HOME/.pi/agent/npm}"
REAL_SETTINGS="${PI_SETTINGS:-$HOME/.pi/agent/settings.json}"
AGENT_DIR="${PI_BENCH_AGENT_DIR:-/tmp/pi-bench-sandbox}"
SANDBOX_NPM="$AGENT_DIR/npm"
JITI_CACHE="${JITI_CACHE_DIR:-/tmp/jiti}"
RUNS=2
COLD=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--cold) COLD=1; shift ;;
	--runs) RUNS="${2:?--runs needs a number}"; shift 2 ;;
	*) break ;;
	esac
done

# One-time sandbox setup: copy the real npm dir so installed packages load.
if [[ ! -d "$SANDBOX_NPM/node_modules" ]]; then
	echo "Setting up sandbox at $AGENT_DIR (one-time copy of $REAL_NPM)…" >&2
	mkdir -p "$AGENT_DIR" "$AGENT_DIR/agents" "$AGENT_DIR/sessions"
	cp -a "$REAL_NPM" "$SANDBOX_NPM"
fi

# Model/provider defaults: derive from the real settings.json when present so the
# sandbox mirrors a plausible profile. Override with PI_BENCH_MODEL / PI_BENCH_PROVIDER.
# These only describe the sandbox; pi --help never calls the model.
DEFAULTS=$(PI_SETTINGS="$REAL_SETTINGS" node -e '
	const s = require(process.env.PI_SETTINGS);
	console.log((s.defaultModel || "glm-5.3-flash") + " " + (s.defaultProvider || "hyper"));
' 2>/dev/null || echo "glm-5.3-flash hyper")
MODEL="${PI_BENCH_MODEL:-${DEFAULTS% *}}"
PROVIDER="${PI_BENCH_PROVIDER:-${DEFAULTS#* }}"

write_settings() {
	local json="$1"
	cat > "$AGENT_DIR/settings.json" <<EOF
{ "defaultModel": "$MODEL", "defaultProvider": "$PROVIDER", "packages": $json }
EOF
}

bench_ms() {
	local n=$1; shift
	local s e
	s=$(date +%s%N)
	for _ in $(seq "$n"); do "$@" >/dev/null 2>&1; done
	e=$(date +%s%N)
	echo $(( (e - s) / n / 1000000 ))
}

run_variant() {
	local label="$1" packages="$2"
	if [[ $COLD -eq 1 ]]; then
		rm -rf "$JITI_CACHE"
		local ms
		ms=$(bench_ms 1 env PI_OFFLINE=1 PI_CODING_AGENT_DIR="$AGENT_DIR" pi --help)
		printf '%-42s %6d ms   (cold)\n' "$label" "$ms"
	else
		local ms
		ms=$(bench_ms "$RUNS" env PI_OFFLINE=1 PI_CODING_AGENT_DIR="$AGENT_DIR" pi --help)
		printf '%-42s %6d ms   (warm, %d runs)\n' "$label" "$ms" "$RUNS"
	fi
}

# Default package list: everything in the real settings.json.
packages=("$@")
if [[ ${#packages[@]} -eq 0 ]]; then
	mapfile -t packages < <(PI_SETTINGS="$REAL_SETTINGS" node -e '
		const s = require(process.env.PI_SETTINGS);
		for (const p of s.packages || []) console.log(p.replace(/^npm:/, ""));
	' 2>/dev/null)
fi

echo "pi-plugin-benchmark — machine: $(nproc) cores, $(free -m | awk 'NR==2{print $2}') MB RAM"
echo "sandbox: $AGENT_DIR"
echo

run_variant "(baseline — no packages)" '[]'

for pkg in "${packages[@]}"; do
	write_settings "[\"npm:$pkg\"]"
	run_variant "$pkg (single)" "[\"npm:$pkg\"]"
done

echo
echo "Note: single-package variants include one-time shared costs (pi baseline +"
echo "shared deps), so subtract the baseline and treat results as upper bounds."
