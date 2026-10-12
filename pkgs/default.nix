{ pkgs }:

let
  inherit (pkgs) lib;

  craft-fonts = pkgs.callPackage ./craft-fonts.nix { };

  mkApp = name: args: pkgs.callPackage ./mk-craft-app.nix ({ inherit name craft-fonts; } // args);

  # Per-app differences. Cargo features mirror upstream's
  # packaging/linux/package.sh so builds match the official releases.
  apps = {
    photocraft = {
      displayName = "PhotoCraft";
      description = "Native, open-source image editor with layered PSD/PSB support";
      cargoFeatures = [ "heif" ];
    };
    vectorcraft = {
      displayName = "VectorCraft";
      description = "Native, open-source vector illustration editor for SVG and PDF";
    };
    filmcraft = {
      displayName = "FilmCraft";
      description = "Native, open-source nonlinear video editor";
      extraBuildInputs = [ pkgs.alsa-lib ];
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
    };
    effectcraft = {
      displayName = "EffectCraft";
      description = "Native, open-source motion graphics and compositing tool";
      extraBuildInputs = [ pkgs.alsa-lib ];
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
      extraBuildInputs = [ pkgs.alsa-lib ];
    };
    deckcraft = {
      displayName = "DeckCraft";
      description = "Native, open-source presentation and slide show editor";
      extraBuildInputs = [ pkgs.alsa-lib ];
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
