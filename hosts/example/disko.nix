# Install-time only: nix run github:nix-community/disko -- --mode disko <this file>
# NOT a flake input; runtime filesystems live in filesystems.nix.
{
  disko.devices.disk.main = {
    type = "disk";
    # Filled in during the install runbook (Task 10 Step 3) from
    # `ls -l /dev/disk/by-id/` run IN THE INSTALLER environment. Device names
    # like /dev/sda are not stable once the install USB stick is plugged in
    # (it can itself enumerate as /dev/sda), so a by-id path of the internal
    # disk is required here, not a bare /dev/sdX.
    device = "/dev/disk/by-id/nvme-REPLACE_WITH_YOUR_DISK"; # ls -l /dev/disk/by-id/ in the installer
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@persist" = {
                  mountpoint = "/persist";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}
