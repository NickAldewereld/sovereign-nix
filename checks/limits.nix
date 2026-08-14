# The README states limits. Prose decays quietly, so the ones that can be
# executed are executed here: these tests assert that the bad thing still
# happens. The day one of them fails, a limit has become obsolete and the
# README is wrong until it is rewritten.
#
# Limit under test: reserving the derived SSH port stops the kernel handing it
# out as an ephemeral source port, but it does not stop an explicit bind, so
# an unprivileged local process can still take it. Measured by hand first,
# then written down here.
{ pkgs, self }:
let
  seed = "limits-seed";
  dlib = import ../lib/diversity.nix { inherit (pkgs) lib; };
  port = toString (
    dlib.derive seed "ssh-port" {
      min = 20000;
      max = 59999;
    }
  );
  nc = "${pkgs.netcat}/bin/nc";

  common = {
    imports = [
      self.nixosModules.harden
      self.nixosModules.diversity
    ];
    sovereign.harden.enable = true;
    sovereign.diversity = {
      enable = true;
      inherit seed;
    };
    services.openssh.enable = true;
    users.users.squatter = {
      isNormalUser = true;
      hashedPasswordFile = "/persist/etc/passwd.squatter";
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "sovereign-limits";
  nodes = {
    # sshd owns its own socket, the way it worked before socket activation
    plain = {
      imports = [ common ];
      services.openssh.startWhenNeeded = false;
    };
    # PID 1 owns the socket, which is what the harden module now does
    activated = {
      imports = [ common ];
    };
  };
  testScript = ''
    plain.wait_for_unit("sshd.service")
    # the reservation is in place on both machines
    plain.succeed("grep -qw '${port}' /proc/sys/net/ipv4/ip_local_reserved_ports")

    # THE LIMIT: with sshd holding its own socket there is a window, and
    # reserving the port does not close it. An unprivileged user takes it.
    plain.succeed("systemctl stop sshd")
    plain.succeed(
        "systemd-run --unit=squat --uid=squatter --collect ${nc} -l ${port}"
    )
    plain.wait_until_succeeds("ss -tln | grep -q ':${port} '")
    plain.succeed("ss -tlnp | grep ':${port} ' | grep -q nc")

    # THE FIX: PID 1 binds at boot, so there is no window to take.
    # There is no sshd.service to stop here: the socket unit is the listener,
    # and it is bound from boot until shutdown.
    activated.wait_for_unit("sshd.socket")
    activated.fail(
        "systemd-run --wait --uid=squatter --collect ${nc} -l ${port}"
    )
    activated.succeed("ss -tln | grep -q ':${port} '")
  '';
}
