{
  config,
  lib,
  ...
}:

let
  cfg = config.user.tui.codingAgent;
  usedByIntegration = config.user.tui.tmux.enable || config.user.tui.lazygit.enable;
in
{
  options.user.tui.codingAgent = lib.mkOption {
    type = lib.types.enum [
      "opencode"
      "claude-code"
    ];
    default = "opencode";
    description = "AI coding agent installed and used by the tmux and lazygit integrations.";
  };

  config = lib.mkIf usedByIntegration {
    # Keep installation independent so the non-selected agent can remain
    # available when explicitly enabled.
    user.tui.opencode.enable = lib.mkDefault (cfg == "opencode");
    user.tui.claude-code.enable = lib.mkDefault (cfg == "claude-code");
  };
}
