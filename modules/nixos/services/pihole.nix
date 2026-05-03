{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.pihole;
  piholeHost = "pihole.${config.homelab.domain}";
  envFile = "/run/pihole-ftl.env";
  proxiedHosts = lib.pipe config.services.caddy.virtualHosts [
    builtins.attrNames
    (builtins.filter (
      host: host != config.homelab.domain && lib.hasSuffix ".${config.homelab.domain}" host
    ))
    lib.unique
  ];
in
{
  options.homelab.pihole = {
    enable = lib.mkEnableOption "Pi-hole DNS filtering";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.hostIPv4 != null;
        message = "Set homelab.hostIPv4 when Pi-hole is enabled.";
      }
    ];

    services.pihole-ftl = {
      enable = true;
      openFirewallDNS = true;

      lists = [
        {
          url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/multi.txt";
          description = "HaGeZi Multi Normal";
        }
      ];

      settings = {
        dns = {
          upstreams = [
            "1.1.1.1"
            "1.0.0.1"
          ];

          reply.host = {
            force4 = true;
            IPv4 = config.homelab.hostIPv4;
          };
        };

        # Pi-hole's structured local host records have not been resolving
        # these names reliably, so serve them through raw dnsmasq records.
        misc.dnsmasq_lines = [
          "address=/${config.homelab.domain}/${config.homelab.hostIPv4}"
        ]
        ++ map (host: "address=/${host}/${config.homelab.hostIPv4}") proxiedHosts;

        webserver.api.cli_pw = true;
      };
    };

    services.pihole-web = {
      enable = true;
      hostName = piholeHost;
      ports = [ "127.0.0.1:8081" ];
    };

    services.caddy.virtualHosts."${piholeHost}" = {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:8081
      '';
    };

    systemd.services.pihole-gravity-update = {
      description = "Pi-hole gravity refresh";
      after = [
        "network-online.target"
        "pihole-ftl.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "pihole-ftl.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = config.services.pihole-ftl.user;
        Group = config.services.pihole-ftl.group;
      };
      script = ''
        ${lib.getExe config.services.pihole-ftl.piholePackage} -g
      '';
    };

    systemd.timers.pihole-gravity-update = {
      description = "Pi-hole gravity refresh";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30m";
        Unit = "pihole-gravity-update.service";
      };
    };

    systemd.services.pihole-ftl = {
      preStart = ''
        set -eu
        umask 077

        ${lib.getExe' pkgs.coreutils "mkdir"} -p /etc/pihole /var/lib/pihole /var/log/pihole
        ${lib.getExe' pkgs.coreutils "chown"} -R pihole:pihole /etc/pihole /var/lib/pihole /var/log/pihole
        ${lib.getExe' pkgs.coreutils "chmod"} 0700 /etc/pihole /var/lib/pihole /var/log/pihole

        password="$(< ${lib.escapeShellArg config.sops.secrets.pihole_web_password_hash.path})"
        printf 'FTLCONF_webserver_api_pwhash=%s\n' "$password" > ${lib.escapeShellArg envFile}
      '';

      postStop = ''
        ${lib.getExe' pkgs.coreutils "rm"} -f ${lib.escapeShellArg envFile}
      '';

      serviceConfig = {
        EnvironmentFile = [ "-${envFile}" ];
        PermissionsStartOnly = true;
      };
    };

    # Pi-hole needs to own port 53, so we cannot keep the systemd-resolved stub listener.
    services.resolved.enable = lib.mkForce false;
  };
}
