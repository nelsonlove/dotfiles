{
  description = "Nelson's macOS system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, ... }:
    let
      mkDarwinHost = { system, hostname }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit hostname; };
          modules = [
            ./hosts/shared.nix
            ./hosts/${hostname}.nix

            { nixpkgs.overlays = [ (import ./overlays/emacs-mac.nix) ]; }

            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.nelson = import ./home/default.nix;
            }
          ];
        };
    in
    {
      darwinConfigurations = {
        Nelsons-MacBook-Pro = mkDarwinHost {
          system = "aarch64-darwin";
          hostname = "Nelsons-MacBook-Pro";
        };
      };
    };
}
