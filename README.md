# artcraft-flake

Nix flake packaging the [ArtCraft Crafting Apps](https://getartcraft.com/apps):
twelve native, open-source creative apps written in Rust by the ArtCraft team.
Each one is built from source at its latest upstream release, and a scheduled
GitHub Action keeps them up to date.

| Package       | App                                   |
| ------------- | ------------------------------------- |
| `photocraft`  | Image editor (PSD/PSB layers)         |
| `vectorcraft` | Vector illustration (SVG, PDF)        |
| `filmcraft`   | Nonlinear video editor                |
| `lightcraft`  | Photo library and raw developer       |
| `pdfcraft`    | PDF workbench                         |
| `effectcraft` | Motion graphics and compositing       |
| `designcraft` | Page layout and publishing            |
| `wordcraft`   | Word processor                        |
| `soundcraft`  | Digital audio workstation             |
| `deckcraft`   | Presentations and slide shows         |
| `cadcraft`    | Computer-aided design and drafting    |
| `gridcraft`   | Spreadsheets                          |
| `craft-suite` | All of the above (the `default`)      |

Each package installs the GUI (`<app>`), the CLI (`<app>-cli`), and upstream's
desktop entry, MIME types, AppStream metainfo and icons. Linux only
(`x86_64-linux`, `aarch64-linux`).

## Usage

Try one without installing:

```sh
nix run github:jervw/artcraft-flake#photocraft
```

## Binary cache

CI pushes every build to the public Cachix cache
[`artcraft`](https://artcraft.cachix.org). Without it, each app is a large Rust
build that compiles locally (roughly 5 to 20 minutes per app on a desktop
machine).

The flake declares the cache in `nixConfig`, so `nix run`/`nix build` offers to
use it. To trust it permanently, run `cachix use artcraft`, or on NixOS add:

```nix
nix.settings = {
  substituters = [ "https://artcraft.cachix.org" ];
  trusted-public-keys = [ "artcraft.cachix.org-1:DVvueuBTTIU1ZMP8eNCGTr1oYvCfBik3uGicXhM0dXs=" ];
};
```

The cache only holds builds against this flake's own nixpkgs pin. Use
`packages`, not the overlay, and don't set `inputs.nixpkgs.follows` for this
flake, or the derivations change and every app compiles locally.

## NixOS / Home Manager

```nix
{
  inputs.artcraft.url = "github:jervw/artcraft-flake";

  outputs = { nixpkgs, artcraft, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = with artcraft.packages.${pkgs.stdenv.hostPlatform.system}; [
            photocraft
            pdfcraft
          ];
          # or every app: [ artcraft.packages.${pkgs.stdenv.hostPlatform.system}.craft-suite ]
        })
      ];
    };
  };
}
```

There is also `overlays.default`, which adds the apps to your `pkgs`. It builds
them against your nixpkgs, so it misses the cache and compiles locally.

## How updating works

Versions and hashes live in `pkgs/sources/<name>.json`, one file per app, so the
Nix code never needs editing for a release.

`scripts/update.py [NAME ...]` bumps them:

- Apps track their newest `vX.Y.Z` git tag. The source hash comes from
  `nix flake prefetch`, and `cargoHash` from building only `.#<app>.cargoDeps`
  with a fake hash.
- `craft-fonts` has no tags, so it tracks the default branch as
  `0-unstable-YYYY-MM-DD`. The apps embed these fonts at build time through
  `CRAFT_FONTS_DIR`, so a fonts bump rebuilds every app.

`.github/workflows/update.yml` runs every 12 hours (upstream often releases
several times a day):

1. Bump `craft-fonts`. On Mondays, or when started manually with
   *update-nixpkgs*, it also bumps nixpkgs in `flake.lock`.
2. One job per app that has a new release (`scripts/update.py --check`): bump
   it and build it. A craft-fonts or nixpkgs bump rebuilds every app. When
   nothing changed, the run ends after the first job.
3. Commit only the bumps that built. A broken upstream release stays at the
   last good version and doesn't hold back the other apps. The craft-fonts and
   nixpkgs bumps are committed only if every app built against them.

`.github/workflows/ci.yml` checks formatting (`nix fmt -- --check .`, alejandra)
and builds every app on pull requests. Run `nix fmt` to format.

GitHub pauses scheduled workflows in public repositories after 60 days without
repository activity. The update bot's own commits count as activity, but if
upstream goes quiet for that long, re-enable the workflow in the Actions tab.

Both workflows push their builds to Cachix through the repository variable
`CACHIX_CACHE` (`artcraft`) and the repository secret `CACHIX_AUTH_TOKEN`. Forks
without them skip the push.

To add a new app that follows the same upstream layout, add it to `apps` in
`pkgs/default.nix`, create `pkgs/sources/<name>.json` containing `{}`, and run
`scripts/update.py <name>`.

## Notes

- **Tests are not run** (`doCheck = false`). The GUI crates run live GPU tests
  that can't run in the build sandbox, and upstream CI already runs the test
  suites. A green build here means the app compiled and `<app>-cli --version`
  ran. It does not mean the test suite passed.
- Cargo features match upstream's release builds (`packaging/linux/package.sh`),
  e.g. HEIF support in PhotoCraft and LightCraft.
- winit/wgpu load Wayland, X11, Vulkan and GL at runtime. These are added to the
  GUI binary's RPATH, and the app's own library preflight is turned off with
  `<APP>_SKIP_LIB_CHECK=1` (set as a default, so you can override it).
- The ArtCraft Launcher (`storytold/craft-launcher`) is not packaged. Its job is
  to download and self-update the apps, which Nix does instead.
- Based on the nixpkgs PRs by @Cleboost
  ([#571418](https://github.com/NixOS/nixpkgs/pull/571418) and siblings,
  [#572622](https://github.com/NixOS/nixpkgs/pull/572622) for craft-fonts).

## License

The Nix packaging in this repository is licensed under the [MIT License](LICENSE).
The packaged applications keep their upstream licenses: MIT OR Apache-2.0 for
the apps, and SIL OFL 1.1 for the embedded craft-fonts.
