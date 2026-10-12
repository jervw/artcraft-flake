{pkgs}: let
  inherit (pkgs) lib;

  craft-fonts = pkgs.callPackage ./craft-fonts.nix {};

  mkApp = name: args: pkgs.callPackage ./mk-craft-app.nix ({inherit name craft-fonts;} // args);

  # Per-app differences. Cargo features mirror upstream's
  # packaging/linux/package.sh so builds match the official releases.
  apps = {
    photocraft = {
      displayName = "PhotoCraft";
      description = "Native, open-source image editor with layered PSD/PSB support";
      cargoFeatures = ["heif"];
    };
    vectorcraft = {
      displayName = "VectorCraft";
      description = "Native, open-source vector illustration editor for SVG and PDF";
    };
    filmcraft = {
      displayName = "FilmCraft";
      description = "Native, open-source nonlinear video editor";
      extraBuildInputs = [pkgs.alsa-lib];
    };
    lightcraft = {
      displayName = "LightCraft";
      description = "Native, open-source photo library and raw developer";
      cargoFeatures = [
        "lightcraft/heif"
        "lightcraft-cli/heif"
      ];
    };
    pdfcraft = {
      displayName = "PdfCraft";
      description = "Native, open-source PDF workbench: read, organize, combine, split and secure";
      # rten-gemm's AVX512-VNNI path calls `_mm512_dpbusd_epi32`, whose LLVM
      # intrinsic signature doesn't match nixpkgs' LLVM ("intrinsic signature
      # mismatch for llvm.x86.avx512.vpdpbusd.512"). Drop that dispatch so it
      # falls back to the AVX2/AVX512 kernels (same fix as nixpkgs PR #571437).
      # The glob makes this a no-op if the crate goes away.
      extraAttrs.postPatch = ''
        for f in "$cargoDepsCopy"/*/rten-gemm-*/src/i8dot.rs; do
          [ -f "$f" ] || continue
          sed -i '/Avx512VnniIsa::new()/,+2d' "$f"
          if grep -q 'Avx512VnniIsa::new()' "$f"; then
            echo "rten-gemm patch did not apply to $f" >&2
            exit 1
          fi
        done
      '';
    };
    effectcraft = {
      displayName = "EffectCraft";
      description = "Native, open-source motion graphics and compositing tool";
      extraBuildInputs = [pkgs.alsa-lib];
    };
    designcraft = {
      displayName = "DesignCraft";
      description = "Native, open-source page layout and publishing editor";
    };
    wordcraft = {
      displayName = "WordCraft";
      description = "Native, open-source word processor";
    };
    soundcraft = {
      displayName = "SoundCraft";
      description = "Native, open-source digital audio workstation";
      extraBuildInputs = [pkgs.alsa-lib];
    };
    deckcraft = {
      displayName = "DeckCraft";
      description = "Native, open-source presentation and slide show editor";
      extraBuildInputs = [pkgs.alsa-lib];
    };
    cadcraft = {
      displayName = "CADCraft";
      description = "Native, open-source computer-aided design and drafting";
    };
    gridcraft = {
      displayName = "GridCraft";
      description = "Native, open-source spreadsheet editor";
    };
  };

  appPackages = lib.mapAttrs mkApp apps;
in
  appPackages
  // {
    inherit craft-fonts;

    craft-suite = pkgs.symlinkJoin {
      name = "craft-suite";
      paths = lib.attrValues appPackages;
      meta = {
        description = "All twelve ArtCraft Crafting Apps";
        homepage = "https://getartcraft.com/apps";
        platforms = lib.platforms.linux;
      };
    };
  }
