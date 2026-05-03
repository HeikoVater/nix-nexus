{
  config,
  homeModules,
  lib,
  ...
}:

let
  cfg = config.user.profile;
  stylixDconfTargets = [
    "gtk"
    "gnome"
    "eog"
    "gnome-text-editor"
  ];
in
{
  imports = [
    homeModules
  ];

  options.user.profile.kind = lib.mkOption {
    type = lib.types.enum [
      "headless"
      "workstation"
    ];
    # Host-family common modules normally set this through
    # `home-manager.sharedModules`. The fallback keeps standalone Home Manager
    # profiles headless-safe unless they override it explicitly.
    default = "headless";
    description = "Profile class used for repo-wide Home Manager defaults.";
  };

  config = {
    programs.home-manager.enable = true;

    # These Stylix targets emit dconf settings. Keep them headless-safe by
    # default while leaving workstation profiles automatic.
    stylix.targets = lib.genAttrs stylixDconfTargets (_: {
      enable = lib.mkDefault (cfg.kind == "workstation");
    });
  };
}
