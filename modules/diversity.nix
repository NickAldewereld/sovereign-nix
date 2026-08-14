# Deterministic per-host diversity: same seed, same machine; different seed,
# different machine. The seed is defense-in-depth, not a secret — but keep it
# out of public repos.
{ config, lib, ... }:
let
  cfg = config.sovereign.diversity;
  dlib = import ../lib/diversity.nix { inherit lib; };
  sshPort = dlib.derive cfg.seed "ssh-port" {
    min = 20000;
    max = 59999;
  };
  # One message for both the assertion and the warning, so a user who trips
  # either one is told the same thing.
  exampleSeedMessage = ''
    sovereign.diversity: the example seed is in use. Its SSH port is derivable
    from the public repository by anyone. Rebuild with the per-host seed:

      nixos-rebuild switch --flake /etc/nixos#example \
        --override-input hostSeed path:/persist/etc/sovereign/seed.d

    That directory must contain a file named `seed` and nothing else; its whole
    contents are copied into the world-readable Nix store. Set
    `sovereign.diversity.allowExampleSeed = true` only for CI and the example
    host.'';
in
{
  options.sovereign.diversity = {
    enable = lib.mkEnableOption "deterministic per-host diversity";
    seed = lib.mkOption {
      type = lib.types.str;
      default = "__example__";
      description = "Per-host seed. Keep it out of public repos.";
    };
    allowExampleSeed = lib.mkEnableOption "building on the example seed; for CI and the example host only";
    derived.sshPort = lib.mkOption {
      type = lib.types.port;
      readOnly = true;
      default = sshPort;
      description = "SSH port derived from the seed.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Stopped at evaluation, not activation: an activation script cannot stop a
    # `nixos-rebuild boot` (no activation runs at all) and does not stop
    # `switch` either — switch-to-configuration-ng continues past a failed
    # snippet, and `etc` has already rewritten sshd_config by then.
    assertions = [
      {
        assertion = cfg.seed != "__example__" || cfg.allowExampleSeed;
        message = exampleSeedMessage;
      }
    ];

    warnings = lib.optional (cfg.seed == "__example__") exampleSeedMessage;

    services.openssh.ports = [ sshPort ];

    # MAC randomisation is a privacy measure, not a hardening one: it stops a
    # network from tracking this host across visits. It does not shrink the
    # attack surface.
    networking.networkmanager.wifi.macAddress = "random";
    networking.networkmanager.ethernet.macAddress = "random";

    boot.kernel.sysctl = {
      # The derived range overlaps the kernel's ephemeral source-port range
      # (net.ipv4.ip_local_port_range, 32768-60999 by default). Reserving the
      # port stops the kernel from ever handing it out as a source port.
      #
      # Measured on a test host, so the limits are known rather than assumed:
      # an ESTABLISHED outbound connection on the port does NOT stop sshd from
      # restarting, because sshd sets SO_REUSEADDR. What does stop it is a
      # local process that LISTENS on the port while sshd is down, and this
      # sysctl does not prevent that: it excludes automatic allocation, not an
      # explicit bind. Treat it as hygiene, not a control.
      # Overlap found by Rick Okkersen.
      "net.ipv4.ip_local_reserved_ports" = toString sshPort;

      # Harmless per-host tuning inside safe margins: every host fingerprints
      # differently without behaving differently.
      "vm.swappiness" = dlib.derive cfg.seed "vm.swappiness" {
        min = 30;
        max = 70;
      };
      "net.core.somaxconn" = dlib.derive cfg.seed "net.core.somaxconn" {
        min = 2048;
        max = 8192;
      };
    };
  };
}
