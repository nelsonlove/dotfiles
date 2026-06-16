{
  description = "Nelson's macOS + NixOS system configurations";

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

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    # vault-mcp — source-only input. The upstream flake pins x86_64-linux, but
    # its derivation (nix/pkgs/vault-mcp.nix) is system-portable when
    # callPackage'd from another pkgs set. Consumed in hosts/pi400.
    vault-mcp-src = {
      url = "github:nelsonlove/obsidian-vault-mcp-server";
      flake = false;
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager, nixos-hardware, sops-nix, ... }:
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

      mkNixosHost = { system, hostname, extraModules ? [] }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit hostname inputs; };
          modules = [
            ./hosts/${hostname}
          ] ++ extraModules;
        };
    in
    {
      darwinConfigurations = {
        Nelsons-MacBook-Pro = mkDarwinHost {
          system = "aarch64-darwin";
          hostname = "Nelsons-MacBook-Pro";
        };
        Nelsons-MacBook-Air = mkDarwinHost {
          system = "aarch64-darwin";
          hostname = "Nelsons-MacBook-Air";
        };
        Nelsons-Virtual-Machine = mkDarwinHost {
          system = "aarch64-darwin";
          hostname = "Nelsons-Virtual-Machine";
        };
      };

      nixosConfigurations = {
        pi400 = mkNixosHost {
          system = "aarch64-linux";
          hostname = "pi400";
          extraModules = [
            nixos-hardware.nixosModules.raspberry-pi-4
            sops-nix.nixosModules.sops
          ];
        };
      };
    };
}
