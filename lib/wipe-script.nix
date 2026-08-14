# Shell text that rolls the btrfs @root subvolume back to empty. Used verbatim
# in the initrd (busybox-compatible) and in the VM test. No `set -e` (initrd
# sh doesn't reliably support it) — failure paths are handled explicitly so
# the script never silently leaves a machine unbootable or half-wiped.
{
  device,
  mountpoint ? "/btrfs_tmp",
  persistDirs ? [ ],
  # Keep the root of the boot that just ended as @root_prev, so on-disk traces
  # of an incident survive the reboot that ended it. Exactly one generation:
  # the next boot deletes it.
  keepPrevious ? true,
  # Overridable so the VM test can feed a kernel command line of its own.
  cmdlineFile ? "/proc/cmdline",
}:
let
  mkdirPersist = builtins.concatStringsSep "\n" (
    map (p: "    mkdir -p ${mountpoint}/@persist${p}") persistDirs
  );
  replaceRoot =
    if keepPrevious then
      "mv ${mountpoint}/@root ${mountpoint}/@root_prev"
    else
      "delete_subvol ${mountpoint}/@root";
in
''
    # Nested subvolumes must go first: systemd creates /var/lib/machines and
    # /var/lib/portables as subvolumes on btrfs, and a subvolume with children
    # cannot be deleted ("Directory not empty").
    delete_subvol() {
      btrfs subvolume list -o "$1" | cut -f 9 -d ' ' | while read -r sub; do
        btrfs subvolume delete "${mountpoint}/$sub"
      done
      btrfs subvolume delete "$1"
    }

    mkdir -p ${mountpoint}
    if mount -o subvol=/ ${device} ${mountpoint}; then
      skip_root=0
      # Escape hatch for incident response: add `sovereign.nowipe` to the
      # kernel command line in the boot loader and this boot keeps its root
      # instead of rolling it back. /persist bind mounts are still set up, so
      # the machine boots normally.
      if grep -q sovereign.nowipe ${cmdlineFile}; then
        echo "sovereign-nix impermanence: sovereign.nowipe set, keeping the current root"
        skip_root=1
      fi
      if [ "$skip_root" = 0 ] && [ -e ${mountpoint}/@root_prev ]; then
        if ! delete_subvol ${mountpoint}/@root_prev; then
          echo "sovereign-nix impermanence: ERROR: cannot delete @root_prev, keeping old root"
          skip_root=1
        fi
      fi
      if [ "$skip_root" = 0 ]; then
        if [ -e ${mountpoint}/@root ]; then
          ${replaceRoot}
        fi
        btrfs subvolume create ${mountpoint}/@root
        mkdir -p ${mountpoint}/@root/etc
        : > ${mountpoint}/@root/etc/machine-id
      fi
  ${mkdirPersist}
      # A persistent machine-id must exist before systemd starts, otherwise
      # systemd boots with a transient id and systemd-machine-id-commit fails
      # trying to write over the bind mount.
      if [ ! -s ${mountpoint}/@persist/etc/machine-id ]; then
        mkdir -p ${mountpoint}/@persist/etc
        tr -d '-' < /proc/sys/kernel/random/uuid > ${mountpoint}/@persist/etc/machine-id
      fi
      umount ${mountpoint}
    else
      echo "sovereign-nix impermanence: ERROR: cannot mount ${device}, skipping root wipe"
    fi
''
