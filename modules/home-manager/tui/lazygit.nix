{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.tui.lazygit;
  opencodeEnabled = config.user.tui.opencode.enable;
  commitSubjectCommand = lib.escapeShellArgs [
    "${pkgs.runtimeShell}"
    "-lc"
    "opencode run --command commit-subject --format json 2>/dev/null | ${pkgs.jq}/bin/jq -Rr 'fromjson? | select(.type == \"text\" and .part.metadata.openai.phase == \"final_answer\") | .part.text'"
  ];
in
{
  options.user.tui.lazygit = {
    enable = lib.mkEnableOption "lazygit git TUI";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      delta
      difftastic
    ];

    programs.lazygit = {
      enable = true;

      settings = {
        disableStartupPopups = true;
        notARepository = "quit";

        gui = {
          nerdFontsVersion = "3";
          showNumstatInFilesView = true;
        };

        os = {
          editPreset = "nvim";
          copyToClipboardCmd = ''
            if [ -n "$TMUX" ]; then
              printf "\033Ptmux;\033\033]52;c;$(printf {{text}} | base64 -w 0)\a\033\\" > /dev/tty
            else
              printf "\033]52;c;$(printf {{text}} | base64 -w 0)\a" > /dev/tty
            fi
          '';
        };

        git.pagers = [
          {
            pager = ''delta --dark --side-by-side --paging=never --line-numbers --hyperlinks --hyperlinks-file-link-format="lazygit-edit://{path}:{line}"'';
          }
          {
            externalDiffCommand = "difft --color=always --display=side-by-side --background=dark";
          }
        ];

        update.method = "never";
      }
      // lib.optionalAttrs opencodeEnabled {
        customCommands = [
          {
            key = "C";
            context = "files";
            description = "Commit with AI subject suggestion";
            command = "git commit -m {{.Form.Message | quote}}";
            loadingText = "Generating commit subject";
            output = "log";
            prompts = [
              {
                type = "input";
                title = "Commit subject";
                key = "Message";
                initialValue = "{{ runCommand `${commitSubjectCommand}` }}";
              }
            ];
          }
        ];
      };
    };
  };
}
