{ pkgs, tmuxOpencode }:

pkgs.writeShellApplication {
  name = "tmux-git-worktrees";
  runtimeInputs = with pkgs; [
    coreutils
    direnv
    fzf
    git
    gnused
    tmux
  ];
  text = ''
    set -euo pipefail

    cwd="''${1:-$PWD}"
    repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || {
        tmux display-message "Not inside a Git repository"
        exit 0
    }

    current_window=$(tmux display-message -p '#{window_id}')
    tmux set-option -w -q -t "$current_window" @worktree_root "$repo_root"

    repo_name=$(basename "$repo_root")
    tmux_opencode_bin="${tmuxOpencode}/bin/tmux-opencode"

    auto_allow_direnv() {
        local target_path="$1"
        local repo_envrc="$repo_root/.envrc"
        local target_envrc="$target_path/.envrc"

        if [ "$target_path" = "$repo_root" ]; then
            return 0
        fi

        if [ -f "$repo_envrc" ] && [ -f "$target_envrc" ] && cmp -s "$repo_envrc" "$target_envrc"; then
            direnv allow "$target_envrc" >/dev/null 2>&1 || true
        fi
    }

    open_worktree_window() {
        local target_path="$1"
        local new_window

        auto_allow_direnv "$target_path"

        new_window=$(tmux new-window -P -F '#{window_id}' -c "$target_path" -n "$repo_name:$branch")
        tmux set-option -w -q -t "$new_window" @worktree_root "$target_path"

        if [ "$target_path" != "$repo_root" ]; then
            "$tmux_opencode_bin" sidebar "$target_path" "$new_window"
        fi
    }

    selection=$(
        git -C "$repo_root" for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads \
            | fzf \
                --print-query \
                --bind='enter:accept-or-print-query' \
                --prompt="Worktree branch> " \
                --header="Pick a branch or type a new one" \
                --layout=reverse \
                --height=40%
    ) || exit 0

    query=$(printf '%s\n' "$selection" | sed -n '1p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    picked=$(printf '%s\n' "$selection" | sed -n '2p')
    branch="$picked"
    if [ -z "$branch" ]; then
        branch="$query"
    fi
    [ -z "$branch" ] && exit 0

    existing_path=""
    wt=""
    while IFS= read -r line; do
        case "$line" in
            worktree\ *)
                wt="''${line#worktree }"
                ;;
            branch\ refs/heads/*)
                if [ "''${line#branch }" = "refs/heads/$branch" ]; then
                    existing_path="$wt"
                    break
                fi
                ;;
        esac
    done < <(git -C "$repo_root" worktree list --porcelain)

    if [ -n "$existing_path" ]; then
        target_path="$existing_path"
    else
        target_path="$repo_root/.worktrees/$branch"
    fi

    existing_window=$(
        tmux list-windows -F '#{window_id}\t#{@worktree_root}' \
            | while IFS="$(printf '\t')" read -r window_id window_root; do
                if [ "$window_root" = "$target_path" ]; then
                    printf '%s\n' "$window_id"
                    break
                fi
            done
    )

    if [ -n "$existing_window" ]; then
        tmux select-window -t "$existing_window"
        exit 0
    fi

    if [ -n "$existing_path" ]; then
        open_worktree_window "$target_path"
        exit 0
    fi

    mkdir -p "$(dirname "$target_path")"

    if [ -e "$target_path" ]; then
        tmux display-message "Worktree path already exists: $branch"
        exit 1
    fi

    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$repo_root" worktree add "$target_path" "$branch"
    else
        git -C "$repo_root" worktree add -b "$branch" "$target_path"
    fi || {
        tmux display-message "worktree add failed: $repo_name:$branch"
        exit 1
    }

    open_worktree_window "$target_path"
  '';
}
