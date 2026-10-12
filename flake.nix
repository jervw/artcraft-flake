{
  description = "Nix packages for the ArtCraft Apps (getartcraft.com/apps)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    inherit (nixpkgs) lib;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAllSystems (
      pkgs: let
        craftPkgs = import ./pkgs {inherit pkgs;};
      in
        craftPkgs // {default = craftPkgs.craft-suite;}
    );

    # Adds every app (and `craft-suite`) to pkgs.
    overlays.default = final: _prev: import ./pkgs {pkgs = final;};

    # Plain `nix fmt` passes no paths, which would make alejandra read stdin.
    formatter = forAllSystems (pkgs:
      pkgs.writeShellApplication {
        name = "fmt";
        runtimeInputs = [pkgs.alejandra];
        text = ''alejandra "''${@:-.}"'';
      });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        packages = [
          pkgs.python3
          pkgs.git
        ];
      };
    });
  };
}
