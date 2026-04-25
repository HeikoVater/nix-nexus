{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.tui.nvf;
in
{
  options.user.tui.nvf = {
    enable = lib.mkEnableOption "nvf (Neovim)";
  };

  # nvf Home Manager module is imported via home-manager.sharedModules in flake.nix

  config = lib.mkIf cfg.enable {
    programs = {
      nvf = {
        enable = true;
        defaultEditor = true;

        settings.vim = {
          # ═══════════════════════════════════════════════════════════════════
          #  Core Editor Settings
          # ═══════════════════════════════════════════════════════════════════

          viAlias = true;
          vimAlias = true;
          searchCase = "smart";

          options = {
            tabstop = 4;
            shiftwidth = 4;
            scrolloff = 8;
            wrap = false;
            cursorlineopt = "both";
            foldenable = false;
            foldlevel = 99;
            foldlevelstart = 99;
            fillchars = "diff: ";
            diffopt = "filler,internal,algorithm:histogram,indent-heuristic,linematch:60";
          };

          globals = {
            mapleader = ";";
            netrw_banner = 0;
            netrw_liststyle = 3;
          };

          # undoFile.enable = true;

          # Clipboard — neovim auto-detects OSC 52 in modern terminals
          # (works over SSH from kitty/ghostty/wezterm)
          clipboard = {
            enable = true;
            registers = "unnamedplus";
          };

          # ═══════════════════════════════════════════════════════════════════
          #  Visual Enhancements
          # ═══════════════════════════════════════════════════════════════════

          visuals = {
            rainbow-delimiters.enable = true;
            nvim-scrollbar.enable = true;

            cinnamon-nvim = {
              enable = true;
              setupOpts = {
                keymaps.basic = true;
                options.delay = 10;
              };
            };
          };

          ui = {
            smartcolumn = {
              enable = true;
              setupOpts = {
                colorcolumn = null;
                custom_colorcolumn = {
                  py = "88";
                };
              };
            };

            modes-nvim = {
              enable = true;
              setupOpts = {
                setCursorline = true;
                colors.visual = "#FFFFFF";
                line_opacity.visual = 0.25;
              };
            };
          };

          statusline.lualine.enable = true;

          # ═══════════════════════════════════════════════════════════════════
          #  Core Plugins
          # ═══════════════════════════════════════════════════════════════════

          # utility.smart-splits.enable = true;  # tmux integration
          utility.motion.flash-nvim.enable = true;

          utility.outline.aerial-nvim = {
            enable = true;
            mappings.toggle = "<C-Tab>";
            setupOpts = {
              layout.default_direction = "left";
            };
          };

          notes.todo-comments = {
            enable = true;
            mappings = {
              quickFix = "<leader>tdq";
              telescope = "<leader>tds";
            };
          };

          autocomplete.nvim-cmp.enable = true;
          # autocomplete.blink-cmp.enable = true;  # Alternative autocomplete

          # ═══════════════════════════════════════════════════════════════════
          #  Telescope (Fuzzy Finder)
          # ═══════════════════════════════════════════════════════════════════

          telescope = {
            enable = true;
            mappings = {
              findProjects = "<leader>fp";
              findFiles = "<leader>ff";
              liveGrep = "<leader>fg";
              buffers = "<leader>fb";
              helpTags = "<leader>fh";
              open = "<leader>ft";
              resume = "<leader>fr";

              gitFiles = "<leader>fvf";
              gitCommits = "<leader>fvcw";
              gitBufferCommits = "<leader>fvcb";
              gitBranches = "<leader>fvb";
              gitStatus = "<leader>fvs";
              gitStash = "<leader>fvx";

              lspDocumentSymbols = "<leader>flsb";
              lspWorkspaceSymbols = "<leader>flsw";
              lspReferences = "<leader>flr";
              lspImplementations = "<leader>fli";
              lspDefinitions = "<leader>flD";
              lspTypeDefinitions = "<leader>flt";
              diagnostics = "<leader>fld";

              treesitter = "<leader>fs";
            };
          };

          # ═══════════════════════════════════════════════════════════════════
          #  Code Intelligence
          # ═══════════════════════════════════════════════════════════════════

          treesitter = {
            enable = true;
            fold = true;
          };

          lsp.enable = true;

          languages = {
            enableTreesitter = true;

            nix = {
              enable = true;
              format = {
                enable = true;
                type = [ "nixfmt" ];
              };
            };
            markdown.enable = true;
            bash.enable = true;
            python = {
              enable = true;
              format = {
                enable = true;
                type = [ "ruff" ];
              };
            };
            clang.enable = true;
          };

          # Additional vim plugins from nixpkgs
          # startPlugins = with pkgs.vimPlugins; [
          #
          # ];

          # ═══════════════════════════════════════════════════════════════════
          #  Keymaps
          # ═══════════════════════════════════════════════════════════════════

          keymaps = [
            {
              desc = "Exit insert mode using jj";
              key = "jj";
              mode = "i";
              action = "<C-c>";
            }

            {
              desc = "Deactivate highlights";
              key = "//";
              mode = "n";
              action = ":noh<CR>";
            }

            # Window splits
            {
              desc = "Open split left";
              key = "<C-w>h";
              mode = "n";
              action = ":set splitright&<CR>:vsplit<CR>:set splitright<CR>:Explore<CR>";
            }
            {
              desc = "Open split below";
              key = "<C-w>j";
              mode = "n";
              action = ":set splitbelow<CR>:split<CR>:Explore<CR>";
            }
            {
              desc = "Open split above";
              key = "<C-w>k";
              mode = "n";
              action = ":set splitbelow&<CR>:split<CR>:set splitbelow<CR>:Explore<CR>";
            }
            {
              desc = "Open split right";
              key = "<C-w>l";
              mode = "n";
              action = ":set splitright<CR>:vsplit<CR>:Explore<CR>";
            }

            # Git merge
            {
              desc = "Merge: take LOCAL";
              key = "gL";
              mode = "n";
              action = ":diffget LOCAL<CR>";
            }
            {
              desc = "Merge: take REMOTE";
              key = "gR";
              mode = "n";
              action = ":diffget REMOTE<CR>";
            }
            {
              desc = "Merge: take BASE";
              key = "gB";
              mode = "n";
              action = ":diffget BASE<CR>";
            }
            {
              desc = "Next diff";
              key = "]c";
              mode = "n";
              action = "]c";
            }
            {
              desc = "Prev diff";
              key = "[c";
              mode = "n";
              action = "[c";
            }

            # LSP actions
            {
              desc = "Show diagnostics";
              key = "<leader>,";
              mode = "n";
              action = ":lua vim.diagnostic.open_float()<CR>";
            }
            {
              desc = "Code action";
              key = "<leader>.";
              mode = "n";
              action = ":lua vim.lsp.buf.code_action()<CR>";
            }

            # Code folding
            {
              desc = "Toggle current fold";
              key = "<C-Space>";
              mode = "n";
              action = "za";
            }
          ];

          # ═══════════════════════════════════════════════════════════════════
          #  Autocommands
          # ═══════════════════════════════════════════════════════════════════

          autocmds = [
            {
              desc = "Reload buffer when file changes on disk (opencode)";
              event = [
                "FocusGained"
                "BufEnter"
                "CursorHold"
                "CursorHoldI"
              ];
              pattern = [ "*" ];
              command = "if mode() !=# 'c' | checktime | endif";
            }

            {
              desc = "Set tabs for *.nix";
              event = [ "FileType" ];
              pattern = [ "nix" ];
              command = "setlocal tabstop=2 shiftwidth=2";
            }
            {
              desc = "Set tabs for *.js/*.html/*.css";
              event = [ "FileType" ];
              pattern = [
                "js"
                "html"
                "css"
              ];
              command = "setlocal tabstop=2 shiftwidth=2";
            }

            {
              desc = "Save view";
              event = [ "BufWinLeave" ];
              pattern = [ "*" ];
              command = "silent! mkview";
            }
            {
              desc = "Load view";
              event = [ "BufWinEnter" ];
              pattern = [ "*" ];
              command = "silent! loadview";
            }
          ];
        };
      };
    };
  };
}
