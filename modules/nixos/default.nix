{
  imports = [
    ./secrets.nix
    ./impermanence.nix
    ./caddy.nix
    ./pihole.nix
    ./mosquitto.nix
    ./home-assistant.nix
    ./zigbee2mqtt.nix
    ./backups.nix
    ./auto-upgrade.nix
    ./nh.nix
    ./coolercontrol.nix
    ./homepage-dashboard.nix
  ];

  # Root is tmpfs, so user accounts need to be recreated from declarative
  # config on every activation instead of preserving mutable shadow state.
  users.mutableUsers = false;
}
