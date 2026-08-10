# Pure seed derivation. No module logic here.
{ lib }:
rec {
  # hexToInt "1a" -> 26
  hexToInt =
    s:
    let
      digits = lib.stringToCharacters "0123456789abcdef";
      val = c: lib.lists.findFirstIndex (x: x == c) (throw "invalid hex char: ${c}") digits;
    in
    lib.foldl' (acc: c: acc * 16 + val c) 0 (lib.stringToCharacters (lib.toLower s));

  # derive seed name { min, max } -> deterministic int in [min, max]
  derive =
    seed: name:
    { min, max }:
    assert lib.assertMsg (max > min) "derive: max must be > min";
    let
      h = builtins.hashString "sha256" "sovereign-nix:${seed}:${name}";
      n = hexToInt (builtins.substring 0 12 h);
    in
    min + lib.mod n (max - min + 1);
}
