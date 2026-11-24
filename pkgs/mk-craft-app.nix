# Generic builder shared by every Crafting App. All twelve upstream repos use the
# same layout: a Cargo workspace with `apps/<name>` (GUI) and `apps/<name>-cli`,
# icons in `assets/app-icon/hicolor`, and desktop/mime/metainfo files in
# `packaging/linux/`. Installing upstream's own metadata (instead of
# makeDesktopItem) keeps this file free of per-release maintenance.
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  versionCheckHook,
  craft-fonts,
  # Libraries winit/wgpu dlopen at runtime.
  libGL,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxkbcommon,
  libxrandr,
  vulkan-loader,
  wayland,
  # Per-app arguments.
  name,
  displayName,
  description,
  cargoFeatures ? [],
  extraBuildInputs ? [],
  extraNativeBuildInputs ? [],
  extraRuntimeDeps ? [],
  extraAttrs ? {},
}: let
  source = lib.importJSON (./sources + "/${name}.json");
  appId = "ai.storyteller.${name}";
  envPrefix = lib.toUpper name;

  runtimeDeps =
    [
      libGL
      libx11
      libxcb
      libxcursor
      libxi
      libxkbcommon
      libxrandr
      vulkan-loader
      wayland
    ]
    ++ extraRuntimeDeps;
in
  rustPlatform.buildRustPackage (
    finalAttrs:
      {
        pname = name;
        inherit (source) version;

        __structuredAttrs = true;
        strictDeps = true;

        src = fetchFromGitHub {
          owner = "storytold";
          repo = name;
          tag = "v${finalAttrs.version}";
          inherit (source) hash;
        };

        # An empty cargoHash makes the update script's prefetch report the real one.
        cargoHash =
          if source.cargoHash == ""
          then lib.fakeHash
          else source.cargoHash;

        env = {
          CRAFT_FONTS_DIR = "${craft-fonts}";
          CRAFT_FONTS_REQUIRED = "1";
          "${envPrefix}_BUILD_DATE" = source.date;
        };

        # fetchCargoVendor only vendors Cargo.lock's [[package]] entries, so a
        # [patch] that the lockfile records as [[patch.unused]] points into a
        # vendored git source that lacks the crate, and cargo fails with "patch
        # location ... does not contain packages matching". Unused patches don't
        # affect resolution, so drop them from the root manifest. Cargo.lock is left
        # alone because cargoSetupPostPatchHook compares it against the vendor copy.
        # This is prePatch, not postPatch, so per-app extraAttrs.postPatch can't
        # override it.
        prePatch = ''
          unusedPatches=$(awk '
            /^\[\[patch\.unused\]\]/ { u = 1; next }
            u && /^name = / { gsub(/"/, "", $3); print $3; u = 0 }
          ' Cargo.lock)
          if [ -n "$unusedPatches" ]; then
            echo "dropping unused [patch] entries: $unusedPatches"
            awk -v names="$unusedPatches" '
              BEGIN { split(names, a, /[ \n]+/); for (i in a) drop[a[i]] = 1 }
              /^\[/ { inPatch = ($0 ~ /^\[patch\./) }
              inPatch && /^[A-Za-z0-9_-]+[ \t]*=/ {
                key = $0; sub(/[ \t]*=.*/, "", key)
                if (key in drop) {
                  if ($0 !~ /}/) { print "multi-line [patch] entry for " key > "/dev/stderr"; exit 1 }
                  next
                }
              }
              { print }
            ' Cargo.toml > Cargo.toml.tmp
            mv Cargo.toml.tmp Cargo.toml
          fi
        '';

        cargoBuildFlags =
          [
            "--package=${name}"
            "--package=${name}-cli"
          ]
          ++ lib.optionals (cargoFeatures != []) ["--features=${lib.concatStringsSep "," cargoFeatures}"];

        # Upstream CI runs the test suites, and the GUI crates run live GPU tests that
        # are too slow (or impossible) in the sandbox. Skipping them keeps automated
        # bumps fast; the install check below still runs the built CLI.
        doCheck = false;

        nativeBuildInputs =
          [
            pkg-config
            makeWrapper
          ]
          ++ extraNativeBuildInputs;

        buildInputs = extraBuildInputs;

        postInstall = ''
          linux=packaging/linux
          install -Dm644 $linux/${appId}.desktop -t $out/share/applications
          if [ -f $linux/${appId}.mime.xml ]; then
            install -Dm644 $linux/${appId}.mime.xml $out/share/mime/packages/${appId}.xml
          fi
          if [ -f $linux/${appId}.metainfo.xml.in ]; then
            mkdir -p $out/share/metainfo
            sed -e "s/@VERSION@/${finalAttrs.version}/g" -e "s/@DATE@/${source.date}/g" \
              $linux/${appId}.metainfo.xml.in > $out/share/metainfo/${appId}.metainfo.xml
          fi

          mkdir -p $out/share/icons
          cp -R assets/app-icon/hicolor $out/share/icons/

          docdir=$out/share/doc/${name}
          install -Dm644 -t $docdir README.md LICENSE-MIT LICENSE-APACHE
          for lic in ${craft-fonts}/fonts/*/OFL.txt; do
            install -Dm644 "$lic" "$docdir/OFL-$(basename "$(dirname "$lic")").txt"
          done
        '';

        # Runs after the fixup hooks shrink the RPATH, so these entries survive.
        # The library preflight (where an app has one) reads `ldconfig -p`, which on
        # non-NixOS hosts lists the system's libraries rather than ours.
        postFixup = ''
          patchelf --add-rpath ${lib.makeLibraryPath runtimeDeps} $out/bin/${name}
          wrapProgram $out/bin/${name} --set-default ${envPrefix}_SKIP_LIB_CHECK 1
        '';

        nativeInstallCheckInputs = [versionCheckHook];
        versionCheckProgram = "${placeholder "out"}/bin/${name}-cli";
        doInstallCheck = true;

        passthru = {inherit source appId;};

        meta = {
          inherit description;
          longDescription = "${displayName}, one of the ArtCraft Crafting Apps.";
          homepage = "https://github.com/storytold/${name}";
          changelog = "https://github.com/storytold/${name}/releases/tag/v${finalAttrs.version}";
          license = with lib.licenses; [
            mit
            asl20
            # Embedded craft-fonts.
            ofl
          ];
          mainProgram = name;
          platforms = lib.platforms.linux;
        };
      }
      // extraAttrs
  )
