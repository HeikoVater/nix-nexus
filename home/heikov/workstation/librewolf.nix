{
  ...
}:

{
  # Personal browser state stays outside the shared GUI module so the
  # reusable module only carries generic LibreWolf defaults.
  programs.librewolf = {
    settings = {
      "browser.startup.homepage" = "https://192.168.188.4:7990/";
    };

    profiles.default = {
      bookmarks = {
        force = true;
        settings = [
          {
            name = "Heimdall";
            url = "http://192.168.188.4:7990";
          }
          {
            name = "ComfyUI";
            url = "http://127.0.0.1:8188";
          }
        ];
      };

      containersForce = true;
      containers = {
        briefcase = {
          color = "blue";
          icon = "briefcase";
          id = 1;
        };
        dollar = {
          color = "green";
          icon = "dollar";
          id = 2;
        };
        fingerprint = {
          color = "red";
          icon = "fingerprint";
          id = 3;
        };
        vacation = {
          color = "orange";
          icon = "vacation";
          id = 4;
        };
        food = {
          color = "purple";
          icon = "food";
          id = 5;
        };
        chill = {
          color = "turquoise";
          icon = "chill";
          id = 6;
        };
      };

      search = {
        force = true;
        default = "g";
        order = [
          "g"
          "gi"
          "a"
          "y"
          "nix"
          "hm"
          "nvf"
        ];
        engines = {
          google = {
            name = "Google";
            urls = [
              {
                template = "https://www.google.com/search";
                params = [
                  {
                    name = "q";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = [ "g" ];
          };

          google-images = {
            name = "Google Images";
            urls = [
              {
                template = "https://www.google.com/search";
                params = [
                  {
                    name = "udm";
                    value = "2";
                  }
                  {
                    name = "q";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = [ "gi" ];
          };

          amazon = {
            name = "Amazon";
            urls = [
              {
                template = "https://www.amazon.de/s";
                params = [
                  {
                    name = "s";
                    value = "exact-aware-popularity-rank";
                  }
                  {
                    name = "k";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = [ "a" ];
          };

          youtube = {
            name = "YouTube";
            urls = [
              {
                template = "https://www.youtube.com/results";
                params = [
                  {
                    name = "search_query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = [ "y" ];
          };

          nix-packages = {
            name = "Nix Packages";
            urls = [
              {
                template = "https://search.nixos.org/packages";
                params = [
                  {
                    name = "channel";
                    value = "25.11";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = [ "nix" ];
          };

          home-manager = {
            name = "Home-Manager";
            urls = [
              {
                template = "https://home-manager-options.extranix.com";
                params = [
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = [ "hm" ];
          };

          nvf = {
            name = "NVF";
            urls = [
              {
                template = "https://nvf.notashelf.dev/search.html";
                params = [
                  {
                    name = "q";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = [ "nvf" ];
          };
        };
      };
    };
  };

  stylix.targets.librewolf.profileNames = [ "default" ];
}
