{ pkgs }:

pkgs.writeShellApplication {
  name = "tmux-opencode";
  runtimeInputs = with pkgs; [
    git
    tmux
  ];
  text = ''
    set -euo pipefail

    mode="''${1:-}"
    cwd="''${2:-$PWD}"
    target_window="''${3:-$(tmux display-message -p '#{window_id}')}"
    root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$cwd")

    tmux set-option -w -q -t "$target_window" @worktree_root "$root"

    case "$mode" in
        popup)
            tmux display-popup -E -w 90% -h 90% -d "$root" opencode
            ;;
        sidebar)
            panes=$(tmux list-panes -t "$target_window" -F '#{pane_id}\t#{pane_title}' \
                | while IFS="$(printf '\t')" read -r pane_id pane_title; do
                    if [ "$pane_title" = "opencode-sidebar" ]; then
                        printf '%s\n' "$pane_id"
                    fi
                done)

            if [ -n "$panes" ]; then
                printf '%s\n' "$panes" | while IFS= read -r pane_id; do
                    [ -n "$pane_id" ] && tmux kill-pane -t "$pane_id"
                done
            else
                tmux select-window -t "$target_window"
                new_pane=$(tmux split-window -h -p 35 -t "$target_window" -c "$root" -P -F '#{pane_id}' opencode)
                tmux select-pane -t "$new_pane" -T opencode-sidebar
            fi
            ;;
        *)
            printf 'Usage: tmux-opencode <popup|sidebar> [cwd] [target-window]\n' >&2
            exit 1
            ;;
    esac
  '';
}
