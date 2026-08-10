{ pkgs }:
let
  dlib = import ../lib/diversity.nix { inherit (pkgs) lib; };
  range = {
    min = 20000;
    max = 59999;
  };
  a = dlib.derive "seed-a" "ssh-port" range;
  a2 = dlib.derive "seed-a" "ssh-port" range;
  b = dlib.derive "seed-b" "ssh-port" range;
  c = dlib.derive "seed-a" "vm.swappiness" {
    min = 30;
    max = 70;
  };
in
assert a == a2; # deterministic
assert a != b; # different seed, different value
assert a >= range.min && a <= range.max;
assert b >= range.min && b <= range.max;
assert c >= 30 && c <= 70;
assert dlib.hexToInt "ff" == 255;
assert dlib.hexToInt "0" == 0;
pkgs.runCommand "diversity-lib-ok" { } "echo ok > $out"
