# Opinionated laptop profile: all four sovereign modules on, plus sane
# laptop power management. Import together with nixosModules.default.
{ lib, ... }:
{
  sovereign.harden.enable = lib.mkDefault true;
  sovereign.diversity.enable = lib.mkDefault true;
  sovereign.impermanence.enable = lib.mkDefault true;
  sovereign.defaults.enable = lib.mkDefault true;

  networking.networkmanager.enable = true;

  # A laptop roams: saved networks that are out of range keep this unit
  # waiting until it times out, which makes every boot and every rebuild
  # report a failure. Nothing here needs to block on the network.
  systemd.services.NetworkManager-wait-online.enable = false;

  services.power-profiles-daemon.enable = false;
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };

  zramSwap.enable = true;
  services.fwupd.enable = true;
  hardware.bluetooth.enable = true;
}
