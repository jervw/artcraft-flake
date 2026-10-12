# AGENTS.md

Notes for coding agents working on this repo. README.md covers what the flake
offers to users. This file covers how it works and what bit us while building it.

## What this is

A Nix flake that builds the 12 ArtCraft Crafting Apps (`storytold/<app>` on
GitHub, all Rust) from source. A GitHub Action bumps them to new upstream
releases automatically and pushes builds to the `artcraft` Cachix cache.

```
flake.nix                 packages, overlay, formatter (alejandra), nixConfig (Cachix)
pkgs/default.nix          app list + per-app differences (features, native deps, patches)
pkgs/mk-craft-app.nix     shared builder for every app
pkgs/craft-fonts.nix      font bundle the apps embed at build time
pkgs/sources/<name>.json  version + hashes; the ONLY thing that changes per release
scripts/update.py         bumps sources/*.json
.github/workflows/        update.yml (scheduled bumps), ci.yml (PR builds)
```

## Rules of thumb

- **Never hand-edit hashes in `pkgs/sources/*.json`.** Run
  `scripts/update.py <name>` (`--force` to recompute at the same version). It gets
  `hash` from `nix flake prefetch` and `cargoHash` by setting it to `""` (the
  builder maps that to `lib.fakeHash`) and reading `got:` from
  `nix build .#<name>.cargoDeps`.
- **`git add` new files before any `nix build`/`eval`.** This is a git flake,
  so untracked files are invisible to Nix and give confusing "does not exist" errors.
- **Prefer upstream's metadata over writing our own.** The builder installs
  `packaging/linux/ai.storyteller.<app>.{desktop,mime.xml,metainfo.xml.in}` and
  `assets/app-icon/hicolor` straight from the source. Don't add `makeDesktopItem`.
  Per-release maintenance must stay at zero, because the bot can't edit Nix code.
- **Keep the builder generic, but think about what a change rebuilds.** Any edit
  to `mk-craft-app.nix` changes all 12 derivations and makes everything in Cachix
  stale (12 long rebuilds in CI). Put app-specific fixes in that app's entry in
  `pkgs/default.nix` (`extraAttrs`, `extraBuildInputs`, ...).
- **Mirror upstream release builds.** Cargo features and packages come from each
  repo's `packaging/linux/package.sh` (e.g. `--features heif` for photocraft,
  `lightcraft/heif,lightcraft-cli/heif` for lightcraft). Check it when adding an
  app or when a release changes behaviour.
- **Format with `nix fmt`** (alejandra; with no arguments it formats `.`). CI
  runs `nix fmt -- --check .`.
- **Look up nixpkgs attribute names** (e.g. with the mcp-nixos tool) instead of
  guessing. The X11 libs are top-level (`libx11`, `libxcursor`, ...), not `xorg.*`.

## Upstream layout (all 12 repos)

- Cargo workspace: `apps/<app>` (GUI), `apps/<app>-cli`, `apps/<app>-web`
  (wasm, not packaged), `crates/*`, `xtask`.
- Release tags are `vX.Y.Z`, often several a day across the suite, so pinned
  versions go stale within hours. `update.py` ignores other tags (the `artcraft`
  repo has junk like `superalpha1`).
- `CRAFT_FONTS_DIR` (absolute path to a craft-fonts checkout) makes `build.rs`
  embed fonts listed in `fonts/manifest.txt` via `include_bytes!`. Apps that
  don't use it ignore the env var. `CRAFT_FONTS_REQUIRED=1` turns a bad path
  into a build error. craft-fonts has no tags, so it tracks `main` as
  `0-unstable-YYYY-MM-DD`.
- `<APP>_BUILD_DATE` / `<APP>_BUILD_SHA` are read with `option_env!` by some
  apps. We set `_BUILD_DATE` from the tag's commit date.
- Some apps run a runtime library preflight (`ldconfig -p`), skipped with
  `<APP>_SKIP_LIB_CHECK=1`. The wrapper sets it as a default.

## Build facts (verified)

- Outputs are large: about 190 MiB per app, mostly two statically linked
  binaries with fonts embedded. Vendored crates (`<app>-<ver>-vendor`) are
  0.6–0.9 GiB each. A full release build takes 10–30+ minutes per app.
  Locally, use `--max-jobs 2 --cores 6` or so, and run builds in the background.
- **Native build inputs:** `alsa-lib` for filmcraft, effectcraft, soundcraft and
  deckcraft. That's all so far.
  - **Lockfiles overstate deps.** `Cargo.lock` lists every optional and
    other-platform crate, so finding `gtk-sys`, `pipewire-sys` or `clang-sys`
    there does NOT mean they're built. filmcraft and photocraft build without
    them. Let the build tell you what's missing.
- **Runtime libraries** (winit/wgpu `dlopen`): Wayland, xkbcommon, X11 libs,
  Vulkan and libGL. They're added to the GUI binary's RPATH in `postFixup`, which
  runs after the fixup hooks' RPATH shrinking, so they survive.
- **Install check:** `versionCheckProgram` is `<app>-cli`. The GUI binary may
  try to open a window.
- **Tests are off** (`doCheck = false`). The GUI crates run live GPU tests, and
  upstream CI runs the suites. So a green build means it compiled and
  `<app>-cli --version` printed the version, nothing more.
- **pdfcraft:** `rten-gemm` (0.26) calls `_mm512_dpbusd_epi32`, which fails with
  nixpkgs' LLVM (`intrinsic signature mismatch for llvm.x86.avx512.vpdpbusd.512`).
  `pkgs/default.nix` sed-deletes the VNNI dispatch in the vendored crate
  (`$cargoDepsCopy/*/rten-gemm-*/src/i8dot.rs`) and fails loudly if the pattern
  stops matching. If another app gains `rten-gemm`, it needs the same patch.
- `fetchCargoVendor` handles git dependencies (effectcraft has 26) with just
  `cargoHash`. No `outputHashes` needed.
- PhotoCraft has been launched on Wayland: the GPU canvas came up.

## Update automation (`.github/workflows/update.yml`)

1. `plan`: bumps nixpkgs (Monday morning runs, or the `update-nixpkgs` input) and
   craft-fonts. If either changed, it builds all apps. Otherwise
   `update.py --check` (just `git ls-remote`) lists the apps with new tags. If
   nothing changed, the run stops after this job.
2. `app` (matrix): `update.py <app>`, then `nix build`. It uploads the new JSON as
   an artifact **only if the build passed**.
3. `commit`: commits the JSONs that built. It commits the nixpkgs/fonts bump only
   if every app job succeeded. Then it pushes to `main` as `github-actions[bot]`.

Gotchas:

- `run:` steps without `shell: bash` don't use `pipefail`, so
  `update.py | tee` would hide failures. The workflow sets `defaults.run.shell: bash`.
- `CACHIX_CACHE` must be a repository **variable** (`vars.`), not a secret.
  `CACHIX_AUTH_TOKEN` is a secret. If the variable is unset, the Cachix step is
  silently skipped.
- `pushFilter: "(-source|-vendor|-vendor-staging)$"` keeps sources and vendored
  crates out of the 5 GB free cache. Keep it.
- Pushes made with `GITHUB_TOKEN` don't trigger other workflows, so bot commits
  don't start `ci.yml` (which runs on PRs and on manual dispatch only).
- Lint workflows with `nix run nixpkgs#actionlint -- .github/workflows/*.yml`.

Useful `gh` commands:

```sh
gh workflow run update.yml -R jervw/artcraft-flake -f update-nixpkgs=true
gh run list -R jervw/artcraft-flake -L 5
gh run view <run-id> -R jervw/artcraft-flake --json jobs \
  --jq '.jobs[] | "\(.name) \(.status) \(.conclusion)"'
# Logs contain escape codes; gh refuses to print them without this flag:
gh api --allow-escape-sequences repos/jervw/artcraft-flake/actions/jobs/<job-id>/logs \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -nE 'error(\[|:)|failed with exit'
```

## Cache

- Cachix `artcraft`, managed signing. The key is in `flake.nix` `nixConfig` and
  in the README.
- The cache only matches derivations built from **this flake's** nixpkgs pin.
  Consumers using `overlays.default` or `inputs.nixpkgs.follows` rebuild
  locally. That's expected; don't "fix" it by changing the overlay.

## Adding an app

1. Check that its repo matches the layout above, and read its
   `packaging/linux/package.sh` for features.
2. Add an entry to `apps` in `pkgs/default.nix`.
3. `echo '{}' > pkgs/sources/<app>.json && git add -A && scripts/update.py <app>`
4. `nix build .#<app>`. Add `extraBuildInputs` (or a patch) only for what
   actually fails.

## Out of scope / prior art

- `storytold/craft-launcher` is not packaged. It downloads and self-updates the
  apps, which conflicts with Nix managing them.
- The `artcraft` repo (the AI studio app) isn't part of the Crafting Apps suite.
- nixpkgs PRs by Cleboost: #571418 photocraft, #571423 lightcraft, #571426
  filmcraft, #571429 vectorcraft, #571432 effectcraft, #571437 pdfcraft, #571440
  designcraft, #572622 craft-fonts. They were stale by several releases within
  days. Useful for prior fixes, not for versions.
- Use `git ls-remote` rather than the GitHub REST API for tag lookups. The
  unauthenticated API allows only 60 requests/hour.
