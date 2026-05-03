{
  description = "NixOS configuration for home servers, workstations, and WSL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    nvf = {
      url = "github:notashelf/nvf/ef1f22efaf4aa37ba9382a7d1807fa8ac9c097fd";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      stylix,
      nixos-wsl,
      nixos-hardware,
      sops-nix,
      disko,
      impermanence,
      nvf,
      git-hooks,
      ...
    }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      mkPkgs =
        allowUnfree:
        import nixpkgs {
          inherit system;
          config.allowUnfree = allowUnfree;
        };

      pkgs = mkPkgs false;
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = false;
      };

      homeManagerExtraSpecialArgs = {
        inherit pkgs-unstable;
        homeModules = ./modules/home-manager;
      };

      homeManagerSharedModules = [
        nvf.homeManagerModules.default
        stylix.homeModules.stylix
        {
          # `useGlobalPkgs` means Home Manager should consume the system
          # package set directly, so Stylix must not try to inject its
          # own nixpkgs overlays at the HM layer.
          stylix.overlays.enable = false;
        }
      ];

      mkHost =
        {
          hostname,
          path,
          allowUnfree ? false,
          withSops ? true,
          withDisko ? false,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs hostname;
          };
          modules = [
            home-manager.nixosModules.home-manager
            {
              home-manager.extraSpecialArgs = homeManagerExtraSpecialArgs;
              home-manager.sharedModules = homeManagerSharedModules;
            }
            impermanence.nixosModules.impermanence
            ./modules/nixos
            path
            {
              nixpkgs.config.allowUnfree = allowUnfree;
            }
          ]
          ++ lib.optional withSops sops-nix.nixosModules.sops
          ++ lib.optional withSops ./modules/nixos/host/secrets-config.nix
          ++ lib.optional withDisko disko.nixosModules.disko;
        };

      mkNixdHomeOptions =
        {
          hostname,
          profile,
          allowUnfree ? false,
        }:
        let
          hostConfig = self.nixosConfigurations.${hostname}.config;
          homeConfiguration = home-manager.lib.homeManagerConfiguration {
            pkgs = mkPkgs allowUnfree;
            extraSpecialArgs = homeManagerExtraSpecialArgs // {
              osConfig = hostConfig;
            };
            modules = homeManagerSharedModules ++ [ profile ];
          };
        in
        homeConfiguration.options;

      mkHostWithNixd =
        hostArgs@{
          hostname,
          allowUnfree ? false,
          ...
        }:
        homeProfiles:
        let
          host = mkHost hostArgs;
        in
        host
        // {
          # Expose the evaluated HM option sets that nixd should use for
          # repo-aware completion. These are rooted in the real host/profile
          # wiring, so custom `user.*` modules appear alongside upstream HM
          # options without adding a custom top-level flake output.
          nixdOptions.homeManager = lib.mapAttrs (
            _: profile:
            mkNixdHomeOptions {
              inherit hostname profile allowUnfree;
            }
          ) homeProfiles;
        };
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system}.pre-commit-check = git-hooks.lib.${system}.run {
        src = self;
        hooks = {
          nixfmt-rfc-style.enable = true;
          check-merge-conflicts.enable = true;
          detect-private-keys.enable = true;
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        inherit (self.checks.${system}.pre-commit-check) shellHook;
      };

      nixosConfigurations = {
        mu =
          mkHostWithNixd
            {
              hostname = "mu";
              path = ./hosts/servers/mu;
              withDisko = true;
            }
            {
              heikov = ./home/heikov/headless.nix;
            };

        desktop =
          mkHostWithNixd
            {
              hostname = "desktop";
              path = ./hosts/workstations/desktop;
              allowUnfree = true;
            }
            {
              heikov = ./home/heikov/workstation.nix;
            };

        laptop =
          mkHostWithNixd
            {
              hostname = "laptop";
              path = ./hosts/workstations/laptop;
              allowUnfree = true;
            }
            {
              heikov = ./home/heikov/workstation.nix;
            };

        wanzl =
          mkHostWithNixd
            {
              hostname = "wanzl";
              path = ./hosts/wsl/wanzl;
              withSops = false;
            }
            {
              heikov = ./home/heikov/headless.nix;
            };
      };
    };
}
