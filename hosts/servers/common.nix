{
  ...
}:

{
  # ─── Host Features ──────────────────────────────────────────────
  host = {
    impermanence.enable = true;
    secrets.enable = true;
    nh.enable = true;
  };

  # ─── Home Manager ───────────────────────────────────────────────
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
  };

  # ─── Basic System ──────────────────────────────────────────────
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "de_DE.UTF-8/UTF-8"
  ];

  # ─── SSH / Shell ───────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  programs.zsh.enable = true;

  # ─── Firewall ──────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # ─── Common Tools ──────────────────────────────────────────────
  programs.git.enable = true;

  # ─── Nix Settings ──────────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
