{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.gui.pegasus;

  mkCollectionMeta =
    col:
    lib.concatStringsSep "\n" (
      [ "collection: ${col.name}" ]
      ++ lib.optional (col.shortname != "") "shortname: ${col.shortname}"
      ++ lib.optional (col.extensions != [ ]) "extensions: ${lib.concatStringsSep ", " col.extensions}"
      ++ lib.optional (col.launch != "") "launch: ${col.launch}"
      ++ map (d: "directory: ${d}") col.directories
    );

  metadataContent = lib.concatStringsSep "\n\n" (map mkCollectionMeta cfg.collections);
in
{
  options.user.gui.pegasus = {
    enable = lib.mkEnableOption "pegasus frontend";

    theme = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Theme directory name and settings identifier.";
            };

            src = lib.mkOption {
              type = lib.types.path;
              description = "Theme source directory or derivation.";
            };
          };
        }
      );
      default = null;
      description = "Pegasus theme to install and activate. When set, settings.txt is Nix-managed.";
    };

    gameDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Directories Pegasus scans for games and metadata files.";
    };

    collections = lib.mkOption {
      default = [ ];
      description = "Game collections for Pegasus metadata generation.";
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Collection display name.";
            };

            shortname = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Short identifier for theme asset matching (e.g. snes, gba, n64).";
            };

            extensions = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "File extensions to include (without dot).";
            };

            launch = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Launch command. Use {file.path} for the ROM path.";
            };

            directories = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional directories to scan for this collection.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.pegasus-frontend ];

    home.file =
      { }
      // lib.optionalAttrs (cfg.theme != null) {
        ".config/pegasus-frontend/themes/${cfg.theme.name}".source = cfg.theme.src;
        ".config/pegasus-frontend/settings.txt".text = "general.theme: ${cfg.theme.name}\n";
      }
      // lib.optionalAttrs (cfg.gameDirectories != [ ]) {
        ".config/pegasus-frontend/game_dirs.txt".text =
          lib.concatStringsSep "\n" cfg.gameDirectories + "\n";
      }
      // lib.optionalAttrs (cfg.collections != [ ]) {
        ".config/pegasus-frontend/metafiles/collections.metadata.pegasus.txt".text = metadataContent + "\n";
      };
  };
}
