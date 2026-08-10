# Kernel, sshd and firewall hardening. Independent of the other modules.
{ config, lib, ... }:
let
  cfg = config.sovereign.harden;
in
{
  options.sovereign.harden = {
    enable = lib.mkEnableOption "kernel, sshd and firewall hardening";
    ssh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Harden sshd (key-only, modern crypto).";
    };
    firewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the default-deny firewall.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        boot.kernel.sysctl = {
          "kernel.kptr_restrict" = 2;
          "kernel.dmesg_restrict" = 1;
          "kernel.unprivileged_bpf_disabled" = 1;
          "net.core.bpf_jit_harden" = 2;
          "kernel.yama.ptrace_scope" = 1;
          "net.ipv4.conf.all.rp_filter" = 1;
          "net.ipv4.conf.default.rp_filter" = 1;
          "net.ipv4.tcp_syncookies" = 1;
          "fs.protected_symlinks" = 1;
          "fs.protected_hardlinks" = 1;
          "fs.protected_fifos" = 2;
          "fs.protected_regular" = 2;
        };
        boot.kernelParams = [
          "init_on_alloc=1"
          "init_on_free=1"
          "page_alloc.shuffle=1"
        ];
        nix.settings.sandbox = true;
        security.sudo.execWheelOnly = true;
      }
      (lib.mkIf cfg.ssh {
        services.openssh.settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
          Ciphers = [
            "chacha20-poly1305@openssh.com"
            "aes256-gcm@openssh.com"
          ];
          KexAlgorithms = [
            "sntrup761x25519-sha512@openssh.com"
            "curve25519-sha256"
          ];
          Macs = [
            "hmac-sha2-512-etm@openssh.com"
            "hmac-sha2-256-etm@openssh.com"
          ];
        };
      })
      (lib.mkIf cfg.firewall { networking.firewall.enable = true; })
    ]
  );
}
