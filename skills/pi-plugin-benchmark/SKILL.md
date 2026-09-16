---
name: pi-plugin-benchmark
description: "Trigger: plugin benchmark, pi startup slow, medir extensiones, jiti cost, cold start, warm start, package loading performance. Measure pi startup cost per package with a sandbox agent dir — no changes to the real install."
license: MIT
metadata:
  author: Yisus423
  version: "1.0"
---

## Activation Contract

Load when measuring how much a pi package (extension/plugin) costs at startup, comparing cold vs warm loads, or producing before/after numbers for a packaging change (e.g. shipping compiled `dist/` instead of raw `.ts`).

## Hard Rules

- Never benchmark against the real `~/.pi/agent` settings; use the sandbox agent dir (`PI_BENCH_AGENT_DIR`, default `/tmp/pi-bench-sandbox`) with a persistent copy of the real npm dir.
- Always run with `PI_OFFLINE=1` so update checks and network stay out of the numbers.
- `pi --help` loads all configured packages: it is the startup proxy. Do not use `pi --version` (CLI parse only).
- Single-package variants include one-time shared costs (pi baseline + shared dependencies). Subtract the baseline and treat results as upper bounds; deltas are not additive.
- Report the machine profile (cores, RAM) with every table: the cost is hardware-sensitive (measured 4× worse on 2 cores / 1.8 GB than on macOS).
- Wiping `/tmp/jiti` for cold measurements is safe (it regenerates) but expect the next real pi start to be slow.

## Method

1. Baseline first: no packages → pi + node floor (~2.7 s on low-end hardware).
2. One package per variant, single, warm (2 runs) → per-package upper bound.
3. For cold: `--cold` wipes `/tmp/jiti` and measures one cold run per variant.
4. For before/after experiments (e.g. esbuild `dist/` pre-compilation), measure
   the same variant twice: once with the raw package, once with the compiled one.

## Verified reference numbers (2 cores / 1.8 GB RAM, pi 0.85.1)

- node baseline: 0.18 s · pi bare: 2.7 s
- pi + 11 packages: 21.5 s warm, ~30 s cold
- One package pre-compiled with esbuild (`dist/*.js`): cold 86 s → **16 s** (5.4×), warm 13.1 s → 10.4 s

Single-package costs from the same machine (warm): pi-btw ~6.6 s, pi-mcp-adapter ~14 s, pi-web-access ~23 s — the heaviest extension tested.

## Scripts

- `scripts/bench.sh` — the runner. Examples:

```bash
# every installed package, warm (2 runs each)
scripts/bench.sh

# specific packages only
scripts/bench.sh pi-mcp-adapter pi-web-access

# cold (first-load) comparison
scripts/bench.sh --cold gentle-pi

# more warm runs for stability
scripts/bench.sh --runs 4 gentle-pi
```

## Sharing Results

Post results to upstream evidence threads (e.g. the pi tracker) with:
machine profile (cores, RAM), pi version, package versions, warm/cold split,
and this sandbox method. Observations from past benchmark sessions can be
recalled from personal memory (Engram topic keys:
`pi-startup-performance-benchmark`, `pi-mcp-adapter-audit-context`).
