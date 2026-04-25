{
  config,
  lib,
  ...
}:

let
  cfg = config.user.cli.shell;
in
{
  options.user.cli.shell = {
    enable = lib.mkEnableOption "shell aliases";
  };

  config = lib.mkIf cfg.enable {
    home = {
      shell = {
        enableShellIntegration = true;
      };
      shellAliases = {
        l = "eza -lh --icons=always --group-directories-first --git";
        ll = "eza -lha --icons=always --group-directories-first --git";
        lt = "eza --icons=always --tree --git-ignore";

        cat = "bat";
        help = "bat --plain --language=help";

        top = "btop";

        df = "duf";
        du = "dust";

        tl = "tmux ls";
        ta = "tmux attach -t";
        ts = "tmux new-session -s";
        td = "tmux detach";
        tks = "tmux kill-session -t";
        tkall = "tmux kill-server";

        nr = "nh os switch";
        nu = "nh os switch --update";
        nt = "nh os test --impure";

        nl = "nh os info";
        ngc = "nh clean all --keep 3";

        ns = "nh search";
      };
    };
  };
}
