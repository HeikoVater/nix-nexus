{
  inputs,
  lib,
  ...
}:

{
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];

  # ─── Host Features ──────────────────────────────────────────────
  host = {
    impermanence.enable = false;
    secrets.enable = false;
    nh.enable = true;
  };

  # ─── Home Manager ───────────────────────────────────────────────
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
  };

  # ─── WSL Platform ───────────────────────────────────────────────
  wsl.enable = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # ─── Basic System ──────────────────────────────────────────────
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  programs.zsh.enable = true;
  programs.git.enable = true;

  # ─── Nix Settings ──────────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
