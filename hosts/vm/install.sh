#!/usr/bin/env bash
# Installs the sovereign-nix demo host onto a blank disk. Run this from inside
# a NixOS installer, in a virtual machine you are happy to destroy. It ERASES
# the disk you point it at.
#
#   sudo bash install.sh [disk] [flake]
#
# Defaults: /dev/vda and this repository's `vm` host.
set -euo pipefail

DISK=${1:-/dev/vda}
FLAKE=${2:-github:NickAldewereld/sovereign-nix#vm}

[ -b "$DISK" ] || {
  echo "not a block device: $DISK" >&2
  exit 1
}
echo "This erases everything on $DISK."
read -r -p "Type ERASE to continue: " confirm
[ "$confirm" = ERASE ] || exit 1

parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary btrfs 1MiB 100%
sleep 2

PART="${DISK}1"
mkfs.btrfs -f -L sovereign "$PART"

mount "$PART" /mnt
for sub in @root @nix @persist @home; do btrfs subvolume create "/mnt/$sub"; done
umount /mnt

OPTS="compress=zstd,noatime"
mount -o "subvol=@root,$OPTS" "$PART" /mnt
mkdir -p /mnt/nix /mnt/persist /mnt/home
mount -o "subvol=@nix,$OPTS" "$PART" /mnt/nix
mount -o "subvol=@persist,$OPTS" "$PART" /mnt/persist
mount -o "subvol=@home,$OPTS" "$PART" /mnt/home

# The wipe leaves an empty /etc/machine-id on the root and keeps the real one
# on /persist. On a first install neither exists yet, and the systemd-boot and
# GRUB installers both want to read one, so create it here.
mkdir -p /mnt/persist/etc /mnt/etc
tr -d '-' < /proc/sys/kernel/random/uuid > /mnt/persist/etc/machine-id
cp /mnt/persist/etc/machine-id /mnt/etc/machine-id

nixos-install --flake "$FLAKE" --no-root-password

echo
echo "Done. Reboot, then log in on the console as demo / sovereign."
echo "SSH listens on port 43581, not 22, and only accepts keys."
