{
  hostname,
  pkgs,
  ...
}:

{
  imports = [
    ../common.nix
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Home Manager — heikov user
  # ═══════════════════════════════════════════════════════════════════
  home-manager.users.heikov = import ../../../home/heikov/headless.nix;

  # ═══════════════════════════════════════════════════════════════════
  #  WSL Platform
  # ═══════════════════════════════════════════════════════════════════
  # WSL stays secret-free, so keep the user password mutable on this host.
  users.mutableUsers = true;

  wsl.defaultUser = "heikov";
  networking.hostName = hostname;

  users.users.heikov = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
  };

  # ─── Helper Commands ────────────────────────────────────────────
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "wslcopy" ''
      find . -type f \
        -exec echo "===== {} =====" \; \
        -exec cat {} \; | /mnt/c/Windows/System32/clip.exe
    '')
  ];

  system.stateVersion = "25.05";
}
