# A throwaway VM that runs all four modules, so the claims in the README can
# be checked on a booted machine by anyone, not only by the author.
#
# Two deliberate differences from a real host, both of which would be wrong
# anywhere else:
#
#   * the seed is published here. On a real machine that hands the SSH port to
#     anyone who reads this repository. Here it is the point: the port has to
#     be predictable for the runbook to tell you where to knock.
#   * there is a password in this file, and no disk encryption.
#
# Boot it, break it, delete it. See hosts/vm/README.md.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  networking.hostName = "sovereign-vm";
  networking.useDHCP = true;
  time.timeZone = "Europe/Amsterdam";
  nixpkgs.hostPlatform = "x86_64-linux";

  # BIOS boot on /dev/vda, so `qemu-system-x86_64 -drive file=disk.qcow2`
  # needs no firmware flags and no EFI variable store.
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  # Plain btrfs, no LUKS: the wipe, the port reservation and the bind mounts
  # do not depend on encryption, and a passphrase prompt would make the reboot
  # test manual.
  fileSystems =
    let
      opts = [
        "compress=zstd"
        "noatime"
      ];
      sub = name: {
        device = "/dev/disk/by-label/sovereign";
        fsType = "btrfs";
        options = opts ++ [ "subvol=${name}" ];
      };
    in
    {
      "/" = sub "@root";
      "/nix" = sub "@nix";
      "/home" = sub "@home";
      "/persist" = (sub "@persist") // {
        neededForBoot = true;
      };
    };

  sovereign.harden.enable = true;
  sovereign.defaults.enable = true;

  sovereign.diversity = {
    enable = true;
    # Published on purpose; see the comment at the top of this file. Derives
    # SSH port 43581.
    seed = "sovereign-nix-demo";
  };

  sovereign.impermanence = {
    enable = true;
    device = "/dev/disk/by-label/sovereign";
    persistPaths = [
      "/etc/nixos"
      "/var/lib/nixos"
      "/var/log"
    ];
  };

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # harden closes root's SSH door, so the machine needs somebody else. A
  # password rather than a key, so the runbook does not have to ask you for
  # one. It is in a public file: treat this host as public.
  users.users.demo = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "sovereign";
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}
