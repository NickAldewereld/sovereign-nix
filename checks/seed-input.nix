# The reference host must evaluate purely: its seed is handed to it by the
# flake, never read from a path at evaluation time inside the host.
{ pkgs, self }:
let
  seed = self.nixosConfigurations.example.config.sovereign.diversity.seed;
  hostText = builtins.readFile ../hosts/example/default.nix;
in
assert seed == "__example__";
# The property that actually regressed when --impure was removed: no
# evaluation-time filesystem read is left in the host.
assert builtins.match ".*(pathExists|readFile).*" hostText == null;
pkgs.runCommand "seed-input-ok" { } "echo ok > $out"
