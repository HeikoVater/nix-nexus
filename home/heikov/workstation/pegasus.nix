{
  config,
  ...
}:

let
  retroarchRootDir = config.user.gui.retroarch.rootDir;
in
{
  # Keep ROM library paths and launcher commands in the personal
  # workstation overlay rather than the shared Pegasus module.
  user.gui.pegasus = {
    gameDirectories = [
      "${retroarchRootDir}/roms"
    ];
    collections = [
      {
        name = "Game Boy Advance";
        shortname = "gba";
        extensions = [ "gba" ];
        launch = ''retroarch -L mgba_libretro.so "{file.path}"'';
        directories = [
          "${retroarchRootDir}/roms/Nintendo - Game Boy Advance"
        ];
      }
      {
        name = "Super Nintendo";
        shortname = "snes";
        extensions = [
          "smc"
          "sfc"
        ];
        launch = ''retroarch -L snes9x_libretro.so "{file.path}"'';
        directories = [
          "${retroarchRootDir}/roms/Nintendo - Super Nintendo Entertainment System"
        ];
      }
      {
        name = "Nintendo 64";
        shortname = "n64";
        extensions = [
          "z64"
          "n64"
          "v64"
        ];
        launch = ''retroarch -L mupen64plus_next_libretro.so "{file.path}"'';
        directories = [
          "${retroarchRootDir}/roms/Nintendo - Nintendo 64"
        ];
      }
    ];
  };
}
