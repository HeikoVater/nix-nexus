{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.tui.tmux;
in
{
  options.user.tui.tmux = {
    enable = lib.mkEnableOption "tmux";
  };

  config = lib.mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      keyMode = "vi";

      # ═══════════════════════════════════════════════════════════════════
      #  Plugins
      # ═══════════════════════════════════════════════════════════════════

      plugins = with pkgs.tmuxPlugins; [
        # Copy to system clipboard
        yank

        # Session persistence — save and restore sessions
        {
          plugin = resurrect;
          extraConfig = ''
            set -g @resurrect-capture-pane-contents 'off'
            set -g @resurrect-strategy-nvim 'session'
          '';
        }

        # Automatic session save/restore
        {
          plugin = continuum;
          extraConfig = ''
            set -g @continuum-restore 'on'
            # set -g @continuum-save-interval '15'  # Save every 15 minutes
          '';
        }

        # Status bar
        {
          plugin = dotbar;
          extraConfig = ''
            set -g @tmux-dotbar-bold-current-window
            set -g @tmux-dotbar-right true
            set -g @tmux-dotbar-position bottom
            set -g @tmux-dotbar-ssh-icon '󰌘'
            set -g @tmux-dotbar-ssh-icon-only false
            set -g @tmux-dotbar-ssh-enabled true
          '';
        }
      ];

      # ═══════════════════════════════════════════════════════════════════
      #  Keybindings & Configuration
      # ═══════════════════════════════════════════════════════════════════

      extraConfig =
        let
          mainMod = "M"; # M = Alt, C = Ctrl, S = Shift
          ctrlMod = "${mainMod}-C";
          resizeAmount = "10";
        in
        ''
          # ─── Clear Default Bindings ────────────────────────────────

          unbind -a -T prefix
          unbind -a -T root
          unbind -a -T copy-mode
          # unbind -a -T copy-mode-vi

          # ─── Pane Navigation & Management ─────────────────────────

          # Navigate between panes (mainMod+hjkl)
          bind -n ${mainMod}-h select-pane -L
          bind -n ${mainMod}-j select-pane -D
          bind -n ${mainMod}-k select-pane -U
          bind -n ${mainMod}-l select-pane -R

          # Swap panes (mainMod+Shift+hjkl)
          bind -n ${mainMod}-H swap-pane -d -t '{left-of}'
          bind -n ${mainMod}-J swap-pane -d -t '{down-of}'
          bind -n ${mainMod}-K swap-pane -d -t '{up-of}'
          bind -n ${mainMod}-L swap-pane -d -t '{right-of}'

          # Resize panes (mainMod+Ctrl+hjkl, repeatable)
          bind -n -r ${ctrlMod}-h resize-pane -L ${resizeAmount}
          bind -n -r ${ctrlMod}-j resize-pane -D ${resizeAmount}
          bind -n -r ${ctrlMod}-k resize-pane -U ${resizeAmount}
          bind -n -r ${ctrlMod}-l resize-pane -R ${resizeAmount}

          # Quick resize to percentage widths (mainMod+Ctrl+1/2/3)
          bind -n ${ctrlMod}-1 resize-pane -x 33%
          bind -n ${ctrlMod}-2 resize-pane -x 50%
          bind -n ${ctrlMod}-3 resize-pane -x 66%

          # ─── Pane Splitting ────────────────────────────────────────

          # Split horizontally (mainMod+\)
          bind -n ${mainMod}-'\' split-window -h -c "#{pane_current_path}"

          # Split vertically (mainMod+-)
          bind -n ${mainMod}-'-' split-window -v -c "#{pane_current_path}"

          # ─── Pane Actions ─────────────────────────────────────────

          # Close current pane (mainMod+x)
          bind -n ${mainMod}-x kill-pane

          # Toggle fullscreen/zoom (mainMod+f)
          bind -n ${mainMod}-f resize-pane -Z

          # ─── Tab (Window) Management ──────────────────────────────

          # Create new tab (mainMod+t)
          bind -n ${mainMod}-t new-window -c "#{pane_current_path}"

          # Close current tab (mainMod+Shift+t)
          bind -n ${mainMod}-T kill-window

          # Navigate between tabs (mainMod+[/])
          bind -n ${mainMod}-'[' previous-window
          bind -n ${mainMod}-']' next-window

          # Swap tab positions (mainMod+{/})
          bind -n ${mainMod}-'{' swap-window -d -t -1
          bind -n ${mainMod}-'}' swap-window -d -t +1

          # Direct tab navigation (mainMod+1-9)
          bind -n ${mainMod}-1 select-window -t 1
          bind -n ${mainMod}-2 select-window -t 2
          bind -n ${mainMod}-3 select-window -t 3
          bind -n ${mainMod}-4 select-window -t 4
          bind -n ${mainMod}-5 select-window -t 5
          bind -n ${mainMod}-6 select-window -t 6
          bind -n ${mainMod}-7 select-window -t 7
          bind -n ${mainMod}-8 select-window -t 8
          bind -n ${mainMod}-9 select-window -t 9

          # ─── Git Worktree windows ─────────────────────────────────

          # Create/open git worktree in new tab (mainMod+W)
          # - Prompts for branch name
          # - Worktree path: <repo>/.worktrees/<branch> (slashes replaced with '-')
          # - If path exists already, just open the window there
          # - Window name: repo:branch (repo derived from origin url, fallback to repo dir)
          # bind -n ${mainMod}-W command-prompt -p "Worktree branch:" \
          #   "run-shell -b 'branch="%%"; \
          #     [ -z "$branch" ] && exit 0; \
          #     cwd="#{pane_current_path}"; \
          #     repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0; \
          #     origin=$(git -C "$repo_root" remote get-url origin 2>/dev/null || true); \
          #     repo=""; \
          #     if [ -n "$origin" ]; then \
          #       repo=$(printf "%s" "$origin" | sed -E "s#(.*[:/])([^/]+)(\\.git)?$#\\2#"); \
          #     fi; \
          #     [ -z "$repo" ] && repo=$(basename "$repo_root"); \
          #     wt_dir=".worktrees/$(printf "%s" "$branch" | sed "s#/#-#g")"; \
          #     wt_path="$repo_root/$wt_dir"; \
          #     if [ -e "$wt_path" ]; then \
          #       tmux new-window -c "$wt_path" -n "$repo:$branch"; \
          #       exit 0; \
          #     fi; \
          #     if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then \
          #       git -C "$repo_root" worktree add "$wt_path" "$branch"; \
          #     else \
          #       git -C "$repo_root" worktree add -b "$branch" "$wt_path"; \
          #     fi || { tmux display-message "worktree add failed: $repo:$branch"; exit 1; }; \
          #     tmux new-window -c "$wt_path" -n "$repo:$branch"'"

          # ─── Session Management ────────────────────────────────────

          # Create session
          bind -n ${mainMod}-c display-popup -E 'bash -i -c "read -p \"Session name: \" name; tmux new-session -d -s \$name && tmux switch-client -t \$name"'

          # Find session (Alt+r to rename, Alt+d to delete)
          bind -n ${mainMod}-Tab display-popup -E '\
            session=$(tmux list-sessions -F "#S" | grep -v "^$(tmux display-message -p \"#S\")$" | \
            fzf --reverse \
              --bind "alt-d:execute(tmux kill-session -t {})+reload(tmux list-sessions -F \"#S\" | grep -v \"^$(tmux display-message -p \"#S\")$\")" \
              --header "Enter: switch | Alt-d: delete"); \
            [ -n "$session" ] && tmux switch-client -t "$session"'

          # Rename current session
          bind -n ${mainMod}-r command-prompt -I "#S" "rename-session '%%'"

          # Close current session (mainMod+Shift+x)
          bind -n ${mainMod}-X kill-session

          # Quick session switching
          bind -n ${mainMod}-'.' switch-client -n
          bind -n ${mainMod}-',' switch-client -p
          bind -n ${mainMod}-'/' switch-client -l

          # ─── TUI popups/sidebars ──────────────────────────────────

          # lazygit popup
          bind -n ${mainMod}-g display-popup \
            -d "#{pane_current_path}" \
            -w 80% \
            -h 80% \
            -E "lazygit"

          bind -n ${mainMod}-G display-popup \
            -d "#{pane_current_path}" \
            -w 100% \
            -h 100% \
            -E "lazygit"

          # sops-menu popup
          bind -n ${mainMod}-s run-shell -b 'pane_id=$(tmux display-message -p "#{pane_id}"); pane_path=$(tmux display-message -p "#{pane_current_path}"); tmux display-popup -d "$pane_path" -w 80% -h 80% -E "sops-menu --mode tmux --tmux-pane $pane_id"'

          # opencode popup
          bind -n ${mainMod}-o display-popup -E -w 90% -h 90% -d '#{pane_current_path}' opencode

          # opencode sidebar
          bind -n ${mainMod}-O run-shell -b 'panes=$(tmux list-panes -F "#{pane_id}" -f "#{==:#{pane_title},opencode-sidebar}"); if [ -n "$panes" ]; then for p in $panes; do tmux kill-pane -t "$p"; done; else new=$(tmux split-window -h -p 35 -c "#{pane_current_path}" -P -F "#{pane_id}" opencode); tmux select-pane -t "$new" -T opencode-sidebar; fi'

          # ─── Copy Mode (OSC 52 clipboard via set-clipboard) ────────

          # Toggle copy mode (mainMod+Space)
          bind -n ${mainMod}-Space copy-mode
          bind -T copy-mode-vi ${mainMod}-Space send-keys -X cancel

          # Vi-style selection and copying (OSC 52 handles clipboard sync)
          bind -T copy-mode-vi v send-keys -X begin-selection
          bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
          bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
          bind -T copy-mode-vi Escape send-keys -X cancel

          # Enter copy-mode when scrolling
          bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" \
            "send-keys -M" \
            "copy-mode -e"

          bind -T copy-mode-vi WheelUpPane send-keys -X scroll-up
          bind -T copy-mode-vi WheelDownPane send-keys -X scroll-down

          # Mouse selection copies to buffer (OSC 52 syncs to client clipboard)
          bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-and-cancel

          # ─── Miscellaneous Bindings ───────────────────────────────

          # Reload config (mainMod+R)
          bind -n ${mainMod}-R source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"

          # ─── Terminal Settings ─────────────────────────────────────

          # Enable extended keys for better key support
          set -s extended-keys on
          set -as terminal-features 'xterm*:extkeys'
          set -as terminal-features 'xterm*:clipboard'

          # True color support
          set -s default-terminal tmux-256color
          set -ag terminal-overrides ",xterm*:RGB"

          # OSC 52 clipboard — syncs tmux buffer to client terminal clipboard
          set -g set-clipboard on

          # Allow passthrough for kitty graphics protocol (image preview over SSH)
          set -g allow-passthrough on

          # ─── Window & Pane Settings ───────────────────────────────

          # Prevent automatic window renaming
          set-option -g allow-rename off

          # Start numbering at 1 instead of 0
          set -g base-index 1
          set -g pane-base-index 1
          set-window-option -g pane-base-index 1

          # Renumber windows when one is closed
          set-option -g renumber-windows on

          # ─── Performance & Behavior ───────────────────────────────

          # Larger scrollback buffer
          set -g history-limit 10000

          # Reduce command delay for better responsiveness
          set -s escape-time 1

          # Longer repeat time for repeatable commands
          set -g repeat-time 1000

          # Switch to another session instead of exiting when closing last window
          set -g detach-on-destroy off

          # Enable mouse
          set -g mouse on

          # Enable focus events for vim integration
          # set -g focus-events on

          # ─── Status Bar ─────────────────────────────────────────────
          #
          # set -g status-position top
          # set -g status-justify left
        '';
    };
  };
}
