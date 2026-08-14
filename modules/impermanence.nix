# Ephemeral btrfs root: @root is rolled back to empty on every boot; only
# /persist (and /nix, /home — separate subvolumes) survive. /home is NOT
# wiped, so user-level persistence (~/.bashrc, ~/.config/autostart, ~/.profile)
# survives a reboot. This module is about the system root, not the user.
{ config, lib, ... }:
let
  cfg = config.sovereign.impermanence;
in
{
  options.sovereign.impermanence = {
    enable = lib.mkEnableOption "ephemeral btrfs root, wiped on every boot";
    device = lib.mkOption {
      type = lib.types.str;
      example = "/dev/mapper/cryptroot";
      description = "The btrfs device holding the @root subvolume.";
    };
    persistPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/etc/NetworkManager/system-connections" ];
      description = "Directories bind-mounted from /persist<path>.";
    };
    allowEphemeralConfig = lib.mkEnableOption "keeping the configuration on the root that gets wiped";
    keepPreviousRoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Keep the root of the boot that just ended as the @root_prev subvolume,
        so on-disk traces of an incident survive the reboot that ended it.
        Exactly one generation is kept: the next boot deletes it. Mount it
        read-only to look at it. Set to false to delete the old root outright.

        Volatile evidence (memory, processes, sockets) is gone at any reboot,
        with or without this module.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # A machine that wipes the directory holding its own configuration cannot
    # rebuild itself. Found the hard way: the first install put /etc/nixos on
    # the root, the first boot threw it away, and the machine could no longer
    # be changed from itself. Stopped at evaluation, like the other guards.
    assertions = [
      {
        assertion = cfg.allowEphemeralConfig || lib.elem "/etc/nixos" cfg.persistPaths;
        message = ''
          sovereign.impermanence: /etc/nixos is not in persistPaths, so this
          machine throws its own configuration away at the first boot and
          cannot rebuild itself afterwards.

            sovereign.impermanence.persistPaths = [ "/etc/nixos" ... ];

          If the configuration lives somewhere else on purpose (in /home, or
          only on a remote you deploy from), say so:

            sovereign.impermanence.allowEphemeralConfig = true;
        '';
      }
    ];

    boot.initrd.supportedFilesystems = [ "btrfs" ];

    # This unit only exists to flush a transient machine-id from RAM to disk.
    # Ours already lives on /persist and is bind-mounted in, so the unit fails
    # ("File system /sys is not a memory file system") and leaves every
    # nixos-rebuild switch reporting failure.
    systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

    boot.initrd.postDeviceCommands = lib.mkAfter (
      import ../lib/wipe-script.nix {
        device = cfg.device;
        persistDirs = cfg.persistPaths;
        keepPrevious = cfg.keepPreviousRoot;
      }
    );

    # /etc/machine-id must be in place before systemd PID 1 reads it, hence
    # neededForBoot. The wipe script pre-creates the (empty) mount target;
    # the install runbook pre-creates the /persist source. systemd fills the
    # empty file on first boot and it persists from then on.
    fileSystems = lib.mkMerge (
      [
        {
          "/etc/machine-id" = {
            device = "/persist/etc/machine-id";
            options = [ "bind" ];
            neededForBoot = true;
          };
        }
      ]
      ++ map (p: {
        "${p}" = {
          device = "/persist${p}";
          options = [ "bind" ];
        };
      }) cfg.persistPaths
    );

    # Belt-and-braces: the wipe script (lib/wipe-script.nix) already creates
    # these sources on the persist subvolume before /persist is mounted, since
    # some of them (e.g. /var/lib/nixos, /var/log) are neededForBoot and would
    # otherwise be missing when systemd tries to bind-mount them. This rule
    # covers persistPaths added later that aren't neededForBoot.
    systemd.tmpfiles.rules = map (p: "d /persist${p} 0755 root root -") cfg.persistPaths;
  };
}
