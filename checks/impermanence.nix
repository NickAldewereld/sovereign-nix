{
  pkgs,
  self,
  nixpkgs,
}:
let
  wipe = import ../lib/wipe-script.nix {
    device = "/dev/vdb";
    mountpoint = "/wipe_tmp";
    persistDirs = [
      "/var/lib/nixos"
      "/var/log"
    ];
  };
  wipeScript = pkgs.writeShellScript "sovereign-wipe" wipe;

  # Prove the module wiring, not just the wipe-script text: /etc/machine-id
  # is neededForBoot, and persistPaths produce a bind mount from
  # /persist<path> for each entry.
  sys = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.impermanence
      {
        sovereign.impermanence = {
          enable = true;
          device = "/dev/mapper/cryptroot";
          persistPaths = [ "/var/log" ];
        };
        fileSystems."/" = {
          device = "/dev/mapper/cryptroot";
          fsType = "btrfs";
          options = [ "subvol=@root" ];
        };
        boot.loader.grub.enable = false;
        system.stateVersion = "25.11";
      }
    ];
  };
in
assert sys.config.fileSystems."/etc/machine-id".neededForBoot == true;
assert sys.config.fileSystems."/var/log".device == "/persist/var/log";
assert builtins.elem "bind" sys.config.fileSystems."/var/log".options;
pkgs.testers.runNixOSTest {
  name = "sovereign-impermanence";
  nodes.machine = {
    virtualisation.emptyDiskImages = [ 512 ];
    environment.systemPackages = [ pkgs.btrfs-progs ];
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    # replicate the real subvolume layout on a scratch disk
    machine.succeed("mkfs.btrfs -f /dev/vdb")
    machine.succeed("mkdir -p /mnt/d && mount /dev/vdb /mnt/d")
    machine.succeed("btrfs subvolume create /mnt/d/@root")
    machine.succeed("btrfs subvolume create /mnt/d/@persist")
    # systemd creates /var/lib/machines and /var/lib/portables as subvolumes
    # on btrfs; a subvolume with children cannot be deleted, so the wipe has
    # to clear nested ones first. This is what broke on real hardware.
    machine.succeed("mkdir -p /mnt/d/@root/var/lib")
    machine.succeed("btrfs subvolume create /mnt/d/@root/var/lib/machines")
    machine.succeed("btrfs subvolume create /mnt/d/@root/var/lib/portables")
    machine.succeed("touch /mnt/d/@root/leftover")
    machine.succeed("touch /mnt/d/@persist/keepme")
    machine.succeed("umount /mnt/d")

    # first wipe: root moved aside, fresh root created, persist untouched,
    # and the neededForBoot persist sources exist before anything mounts them
    machine.succeed("${wipeScript}")
    machine.succeed("mount /dev/vdb /mnt/d")
    machine.fail("test -e /mnt/d/@root/leftover")
    machine.succeed("test -e /mnt/d/@root_prev/leftover")
    machine.succeed("test -e /mnt/d/@root_prev/var/lib/machines")
    machine.succeed("test -e /mnt/d/@persist/keepme")
    machine.succeed("test -f /mnt/d/@root/etc/machine-id")
    machine.succeed("test -d /mnt/d/@persist/var/lib/nixos")
    machine.succeed("test -d /mnt/d/@persist/var/log")
    machine.succeed("umount /mnt/d")

    # second wipe: the previous root — nested subvolumes and all — is replaced,
    # not accumulated, and the fresh root really is empty
    machine.succeed("${wipeScript}")
    machine.succeed("mount /dev/vdb /mnt/d")
    machine.fail("test -e /mnt/d/@root_prev/leftover")
    machine.fail("test -e /mnt/d/@root_prev/var/lib/machines")
    machine.fail("test -e /mnt/d/@root/leftover")
    machine.succeed("test -e /mnt/d/@persist/keepme")
  '';
}
