# The public repository must not carry a real identity. Scans the whole tree,
# not a hand-kept list of files, and matches key types and identifier shapes
# rather than only today's literals.
{ pkgs }:
let
  # Shapes, never literals: a check that spelled out the author's username,
  # domains and disk serial would publish exactly what it is meant to catch.
  patterns = builtins.concatStringsSep "|" [
    "ssh-(rsa|ed25519|dss)"
    "ecdsa-sha2-"
    "by-id/(nvme|ata|wwn)-[A-Za-z0-9_.-]*_[A-Za-z0-9]{8,}"
  ];
  mail = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}";
in
# `@openssh.com` is the OpenSSH cipher-suite naming convention in
# modules/harden.nix, not an address. This file is excluded from its own scan,
# which is what lets the positive control below carry live-looking samples.
pkgs.runCommand "no-personal-data-ok" { } ''
  cd ${../.}

  # Positive control. A grep that matches nothing passes for the wrong reason
  # and reads exactly like one that works, so make it match on purpose first.
  cat > $TMPDIR/sample <<'SAMPLE'
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5exampleexample somebody@example.org
  ecdsa-sha2-nistp256 AAAAE2V
  /dev/disk/by-id/nvme-VENDOR_MODEL_S1234567890AB
  SAMPLE
  for p in 'ssh-(rsa|ed25519|dss)' 'ecdsa-sha2-' 'by-id/(nvme|ata|wwn)-[A-Za-z0-9_.-]*_[A-Za-z0-9]{8,}' '${mail}'; do
    grep -qE "$p" $TMPDIR/sample || {
      echo "pattern matches nothing at all, this check is vacuous: $p" >&2
      exit 1
    }
  done

  if grep -rnEi --exclude=no-personal-data.nix '${patterns}' .; then
    echo "personal data found in the public repository" >&2
    exit 1
  fi
  if grep -rnEi --exclude=no-personal-data.nix '${mail}' . | grep -v '@openssh\.com'; then
    echo "e-mail address found in the public repository" >&2
    exit 1
  fi
  echo ok > $out
''
