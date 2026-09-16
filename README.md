# pi-plugin-benchmark

Measure how much each pi package (extension/plugin) costs at startup — with a
sandboxed agent dir, so your real install is never touched.

A [pi skill](https://pi.dev) with a runner script. Works for any pi user on any
hardware; built and verified on a 2-core / 1.8 GB Linux machine where the cost
of plugin loading is hardest to hide.

## Why

pi loads extensions with [jiti](https://github.com/unjs/jiti), which transpiles
TypeScript on every process start. That cost is invisible in docs and release
notes, and it scales with your hardware: the same setup that costs ~5 s on a
modern laptop cost **86 s cold** on a low-end machine. Nobody notices until
they wonder why a coding agent feels slow — on a cheap laptop, on a stream, or
in a CI matrix.

Per-package costs are even more opaque: one plugin can dominate the whole
startup budget while others are nearly free. `pi-plugin-benchmark` turns that
into numbers:

| Variant (single, warm) | Cost |
|---|---|
| pi baseline (no packages) | 2.9 s |
| pi-btw | 6.6 s |
| pi-mcp-adapter | 14.0 s |
| pi-web-access | 22.9 s |

Full methodology and upstream evidence:
[earendil-works/pi#7739](https://github.com/earendil-works/pi/issues/7739).

## What

`scripts/bench.sh` measures `pi --help` (which loads all configured packages)
across variants:

- **baseline** — no packages: the pi + node floor
- **one per package** — single package enabled: per-package upper bound
- **cold mode** (`--cold`) — wipes the jiti cache and measures first-load cost

Design rules:

- Runs in a **sandbox agent dir** (`/tmp/pi-bench-sandbox`, a one-time copy of
  your real npm dir) — your real install and settings are never modified.
- Always runs with `PI_OFFLINE=1` so update checks stay out of the numbers.
- Single-package variants include one-time shared costs: subtract the baseline
  and treat results as upper bounds.

## How

### Install

```bash
# as a pi package (installs the skill)
pi install git:Yisus423/pi-plugin-benchmark

# or copy the skill manually
cp -r skills/pi-plugin-benchmark ~/.pi/agent/skills/
```

### Run

```bash
scripts/bench.sh                      # every installed package, warm
scripts/bench.sh pi-mcp-adapter       # one package
scripts/bench.sh --cold gentle-pi     # cold (first-load) comparison
scripts/bench.sh --runs 4 gentle-pi   # more warm runs for stability
```

### Read

1. Baseline first: that is the floor you pay regardless of plugins.
2. Each single-package number minus the baseline is that package's upper-bound
   cost (shared dependencies make deltas non-additive).
3. Report the machine profile (cores, RAM) with every table — the cost is
   hardware-sensitive.

### Interpret before/after changes

To validate a packaging change (e.g. shipping compiled `dist/` instead of raw
`.ts`), measure the same package twice — once raw, once compiled — and compare
warm and cold. A verified example: pre-compiling one package with esbuild took
its cold start from 86 s to **16 s (5.4×)** with no pi core changes.

## License

MIT
