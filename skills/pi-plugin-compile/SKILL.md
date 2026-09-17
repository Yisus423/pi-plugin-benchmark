---
name: pi-plugin-compile
description: "Trigger: aplicar bundle esbuild, pre-compile extensiones, dist para plugin, jiti lento, compilar paquete pi, aplicar receta dist. Apply the verified esbuild pre-compilation recipe to pi packages — backup, bundle, manifest, verify, rollback."
license: MIT
metadata:
  author: Yisus423
  version: "1.0"
---

## Activation Contract

Load when applying the esbuild `dist/` pre-compilation recipe to a pi package (own or installed), when a package's cold start is dominated by jiti transpilation, or when rolling back a compiled package.

## Hard Rules

- **Always backup first** (`<pkg>.orig-<ts>` beside the package) before touching anything.
- **Externalize every declared bare import** from `package.json` (`dependencies`/`peerDependencies`), plus the host-provided `@earendil-works/*` and `typebox`: they are provided by the running pi via jiti virtual modules; regular deps resolve from node_modules; `node:*` from Node. The bundle must contain ONLY the package's own relative files — bundling the host duplicates pi in memory and breaks registration subtly.
- **Flatten the bundle output** (`--outbase=<entry-dir>` → `dist/*.js`): extensions computing package-root via `dirname(dirname(import.meta.url))` break if the bundle lands in a nested directory.
- **Warn on root-level entries**: an entry file at the package root changes directory depth under `dist/`.
- **Verify after applying**: `pi --help` must exit 0; for real-use confidence, run a real prompt or the RPC `get_state` handshake (see pi-plugin-benchmark SKILL.md).
- **Changes do NOT persist across pi updates**: pi re-syncs installed packages and reverts the manifest. Re-run to re-apply; the durable fix is shipping `dist/` upstream (prepublishOnly), not patching the install.
- Extensions using `createRequire` may fail to load when compiled (upstream: earendil-works pi#238). If a package fails to verify, roll back and note it.

## The Recipe (verified end-to-end, 2 cores / 1.8 GB RAM)

Execute these steps by hand (or have an agent follow them) — an automated
version of this recipe existed and was retired: the recipe has
non-deterministic edge cases (file vs dir entries, re-application after
updates, sandbox sync) that a script handled worse than a careful manual pass.

1. **Backup**: `cp -a <pkg-dir> <pkg-dir>.orig-$(date +%Y%m%d-%H%M%S)`.
2. **Derive the entry**: read `pi.extensions` from the package manifest.
   A directory entry (e.g. `./extensions`) or a file entry (e.g.
   `./index.ts`) both work; note which kind it is.
3. **Derive externals from package.json** — every bare specifier among the
   declared `dependencies`/`peerDependencies`, plus the host-provided
   `@earendil-works`, `typebox`, and `node:*`. Do NOT scan file contents
   with a regex: arbitrary strings produce false positives and broken
   esbuild flags (verified failure mode).
4. **Build** (flatten the output — critical):
   `esbuild <entry-files> --bundle --format=esm --platform=node --target=node20 --outdir=<pkg>/dist --outbase=<entry-dir> $externals`
   File entries: outbase = the file's dir. Dir entries: outbase = that dir.
5. **Manifest**: point `pi.extensions` at `["./dist"]`.
6. **Verify**: `pi --help` exits 0 AND the bundle files sit FLAT directly
   under `dist/` (a nested `dist/extensions/*.js` without index is invisible
   to pi's discovery — a silent no-op, verified failure mode).

Reference numbers (gentle-pi 2.5, one package): cold 86 s → **16 s (5.4×)**, warm 13.1 s → 10.4 s. Real-use verified: persona injection, tool calls, RPC, and TUI renders all work from `dist/`.

## Scripts

None — this skill is a documented recipe, deliberately. Measure with
pi-plugin-benchmark's `scripts/bench.sh`; apply the recipe by hand. Two real
examples from this repo's sessions:

```bash
# gentle-pi (dir entry ./extensions, 11 files → dist/*.js)
esbuild extensions/*.ts --bundle --format=esm --platform=node --target=node20 \
  --outdir=dist --outbase=extensions \
  --external:@earendil-works/* --external:typebox --external:node:*

# pi-btw (file entry ./extensions/btw.ts → dist/btw.js)
esbuild extensions/btw.ts --bundle --format=esm --platform=node --target=node20 \
  --outdir=dist --outbase=extensions \
  --external:@earendil-works/* --external:typebox --external:node:*
```

## When NOT to use this

- During **development** of a package: jiti live-transpiles TS, so edits show up on restart — that DX is a feature. Compile for **published/installed** packages only.
- If the package's cold start is not jiti-dominated: measure first (`pi-plugin-benchmark`), then decide.
