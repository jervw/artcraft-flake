{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

let
  source = lib.importJSON ./sources/craft-fonts.json;
in
stdenvNoCC.mkDerivation {
  pname = "craft-fonts";
  inherit (source) version;

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    inherit (source) rev hash;
  };

  dontConfigure = true;
  dontBuild = true;

  # The apps embed these at build time through CRAFT_FONTS_DIR, which expects
  # upstream's `fonts/` tree (with `fonts/manifest.txt`), not a fontconfig layout.
  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r fonts $out/fonts
    install -Dm644 -t $out/share/doc/craft-fonts \
      ATTRIBUTION.md README.md LICENSE-MIT LICENSE-APACHE

    runHook postInstall
  '';

  passthru.source = source;

  meta = {
    description = "Shared font bundle for the ArtCraft Crafting Apps (CRAFT_FONTS_DIR)";
    homepage = "https://github.com/storytold/craft-fonts";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
