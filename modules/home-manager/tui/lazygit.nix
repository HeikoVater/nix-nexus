{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.tui.lazygit;
  codingAgent = config.user.tui.codingAgent;
  claudeCommitSubjectPrompt = ''
    The staged diff and its summary are provided on standard input.

    Write exactly one Git commit subject line for the staged changes.
    Do not output anything else.

    Requirements:
    - Use imperative mood.
    - Focus on the intent of the change, not a file-by-file summary.
    - Do not end with a period.
    - Prefer 50-60 characters and never exceed 72 characters.
    - Use a prefix like fix:, feat:, refactor:, docs:, test:, or chore: only when it clearly fits.
  '';
  commitSubjectCommand = pkgs.writeShellApplication {
    name = "coding-agent-commit-subject";
    text =
      if codingAgent == "opencode" then
        ''
          ${config.programs.opencode.package}/bin/opencode run --command commit-subject --format json 2>/dev/null \
            | ${pkgs.jq}/bin/jq -Rr 'fromjson? | select(.type == "text" and .part.metadata.openai.phase == "final_answer") | .part.text'
        ''
      else
        ''
          {
            printf 'Staged diff stat:\n'
            ${pkgs.git}/bin/git diff --cached --stat
            printf '\nStaged diff:\n'
            ${pkgs.git}/bin/git diff --cached
          } | ${config.programs.claude-code.finalPackage}/bin/claude \
            --print \
            --output-format text \
            --tools "" \
            --no-session-persistence \
            ${lib.escapeShellArg claudeCommitSubjectPrompt} 2>/dev/null
        '';
  };
in
{
  options.user.tui.lazygit = {
    enable = lib.mkEnableOption "lazygit git TUI";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [ difftastic ];

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
            colorArg = "always";
            externalDiffCommand = "difft --color=always --display=side-by-side --background=dark";
          }
        ];

        update.method = "never";

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
                initialValue = "{{ runCommand `${lib.getExe commitSubjectCommand}` }}";
              }
            ];
          }
        ];
      };
    };
  };
}
