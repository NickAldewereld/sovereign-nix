# A module library nobody can import is not a module library. A relative
# `path:` input makes Nix refuse to read this flake's whole lock file from the
# outside, so every consumer fails with "lock file contains unlocked input"
# before evaluation even starts. `nix flake check` never notices, because it
# only ever evaluates this flake as the root.
{ pkgs, self }:
pkgs.runCommand "consumable-ok" { } ''
  lock=${self}/flake.lock
  # Without this the grep below would fail to open the file, report nothing,
  # and the check would pass for the wrong reason.
  test -f "$lock" || { echo "no flake.lock to check" >&2; exit 1; }

  # Positive control: prove the pattern matches a lock that does contain one.
  printf '%s' '{"nodes":{"x":{"locked":{"type": "path"}}}}' > sample.json
  grep -q '"type": *"path"' sample.json || {
    echo "the pattern matches nothing at all; this check is vacuous" >&2
    exit 1
  }

  if grep -q '"type": *"path"' "$lock"; then
    echo "flake.lock has a path input; consumers cannot lock this flake" >&2
    exit 1
  fi
  echo ok > $out
''
