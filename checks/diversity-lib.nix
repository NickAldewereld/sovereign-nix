{ pkgs }:
let
  dlib = import ../lib/diversity.nix { inherit (pkgs) lib; };
  port = {
    min = 20000;
    max = 59999;
  };
  swappiness = {
    min = 30;
    max = 70;
  };
  somaxconn = {
    min = 2048;
    max = 8192;
  };
  a = dlib.derive "seed-a" "ssh-port" port;
  a2 = dlib.derive "seed-a" "ssh-port" port;
  b = dlib.derive "seed-b" "ssh-port" port;
  c = dlib.derive "seed-a" "vm.swappiness" swappiness;

  # An executable limit, not a feature. The derived values live in a small
  # space (40000 ports, 41 swappiness values, 6145 somaxconn values), so two
  # different seeds can land on the same machine. This pair was found by Ryan
  # Theunissen by brute force, against the claim that a different seed gives a
  # different machine. It does not, and this asserts that it does not, so
  # nobody can quietly put the claim back.
  fingerprint = seed: [
    (dlib.derive seed "ssh-port" port)
    (dlib.derive seed "vm.swappiness" swappiness)
    (dlib.derive seed "net.core.somaxconn" somaxconn)
  ];
in
assert a == a2; # deterministic
assert a != b; # these two happen to differ; in general they need not
assert a >= port.min && a <= port.max;
assert b >= port.min && b <= port.max;
assert c >= 30 && c <= 70;
assert dlib.hexToInt "ff" == 255;
assert dlib.hexToInt "0" == 0;
# The collision, stated as a fact of this design.
assert fingerprint "john-balls-14333" == fingerprint "john-balls-94081";
assert fingerprint "john-balls-14333" == [
  33670
  42
  3377
];
pkgs.runCommand "diversity-lib-ok" { } "echo ok > $out"
