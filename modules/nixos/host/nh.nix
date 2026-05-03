{
  config,
  lib,
  ...
}:

let
  cfg = config.host.nh;
in
{
  options.host.nh = {
    enable = lib.mkEnableOption "nh (Nix helper) with scheduled garbage collection";
  };

  config = lib.mkIf cfg.enable {
    # ─── nh — Nix Helper ───────────────────────────────────────────
    # Provides `nh os build/switch` (nicer output with build trees
    # and diffs) and scheduled garbage collection via `nh clean`.
    #
    # `nh clean` improves on plain `nix-collect-garbage` by also
    # removing stale gcroots and direnv caches. Retention is
    # controlled by --keep (generation count) and --keep-since (age).
    #
    # The clean timer runs weekly by default (NixOS module default).
    # Adjust extraArgs below to change retention policy.
    programs.nh = {
      enable = true;
      clean = {
        enable = true;
        extraArgs = "--keep-since 7d --keep 3";
      };
    };
  };
}
