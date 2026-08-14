{ pkgs, self }:
let
  dlib = import ../lib/diversity.nix { inherit (pkgs) lib; };
  range = {
    min = 20000;
    max = 59999;
  };
  portA = toString (dlib.derive "seed-alpha" "ssh-port" range);
  portB = toString (dlib.derive "seed-beta" "ssh-port" range);
in
assert portA != portB;
pkgs.testers.runNixOSTest {
  name = "sovereign-diversity";
  nodes = {
    alpha = {
      imports = [ self.nixosModules.diversity ];
      sovereign.diversity = {
        enable = true;
        seed = "seed-alpha";
      };
      services.openssh.enable = true;
    };
    beta = {
      imports = [ self.nixosModules.diversity ];
      sovereign.diversity = {
        enable = true;
        seed = "seed-beta";
      };
      services.openssh.enable = true;
    };
  };
  testScript = ''
    for m in [alpha, beta]:
        m.wait_for_unit("sshd.service")
    alpha.succeed("ss -tlnp | grep -q ':${portA} '")
    beta.succeed("ss -tlnp | grep -q ':${portB} '")
    alpha.fail("ss -tlnp | grep -q ':22 '")
    # the derived port overlaps the ephemeral source-port range, so the kernel
    # must be told never to hand it out
    alpha.succeed("grep -qw '${portA}' /proc/sys/net/ipv4/ip_local_reserved_ports")
    beta.succeed("grep -qw '${portB}' /proc/sys/net/ipv4/ip_local_reserved_ports")
  '';
}
