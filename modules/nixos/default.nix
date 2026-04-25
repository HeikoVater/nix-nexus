{
  imports = [
    ./secrets.nix
    ./caddy.nix
    ./mosquitto.nix
    ./home-assistant.nix
    ./zigbee2mqtt.nix
    ./backups.nix
    ./auto-upgrade.nix
    ./nh.nix
  ];
}
