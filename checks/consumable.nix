# A module library nobody can import is not a module library. A relative
# `path:` input makes Nix refuse to read this flake's whole lock file from the
# outside, so every consumer fails with "lock file contains unlocked input"
# before evaluation even starts. `nix flake check` never notices, because it
# only ever evaluates this flake as the root.
{ pkgs, self }:
pkgs.runCommand "consumable-ok" { } ''
  if grep -q '"type": *"path"' ${self}/flake.lock; then
    echo "flake.lock has a path input; consumers cannot lock this flake" >&2
    exit 1
  fi
  echo ok > $out
''
