{
  description = "Secure, sovereign NixOS modules — every boot clean, every claim tested, every limit written down";

  # No `hostSeed` input here. A relative `path:` input cannot be locked by
  # anyone who takes this flake as a dependency: Nix refuses to read the whole
  # lock file and every consumer fails with "lock file contains unlocked
  # input". A module library has to be consumable, so the sentinel is read
  # from the flake source instead, which is just as pure. Your own flake
  # declares its own seed input; see the README.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      seed = nixpkgs.lib.removeSuffix "\n" (builtins.readFile ./example-seed/seed);
    in
    {
      nixosModules = {
        harden = ./modules/harden.nix;
        diversity = ./modules/diversity.nix;
        impermanence = ./modules/impermanence.nix;
        sovereign = ./modules/sovereign.nix;

        # Shipped for months without being an output, so nobody following the
        # README could reach it. Found by consuming this flake from a real
        # machine instead of reading it.
        laptop = ./profiles/laptop.nix;

        default = {
          imports = [
            ./modules/harden.nix
            ./modules/diversity.nix
            ./modules/impermanence.nix
            ./modules/sovereign.nix
          ];
        };
      };

      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit seed; };
        modules = [
          self.nixosModules.default
          self.nixosModules.laptop
          ./hosts/example
          # CI only: lets `nix flake check` evaluate this host on the checked-in
          # sentinel seed. DELETE this when you copy the host — without it the
          # assertion in modules/diversity.nix stops the build.
          { sovereign.diversity.allowExampleSeed = true; }
        ];
      };

      # A throwaway machine anyone can boot, so the two claims that need a
      # running system are checkable without access to the author's hardware.
      # See hosts/vm/README.md.
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          ./hosts/vm
        ];
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;

      checks.${system} = {
        diversity-lib = import ./checks/diversity-lib.nix { inherit pkgs; };
        harden = import ./checks/harden.nix { inherit pkgs self; };
        diversity = import ./checks/diversity.nix { inherit pkgs self; };
        impermanence = import ./checks/impermanence.nix { inherit pkgs self nixpkgs; };
        sovereign = import ./checks/sovereign.nix { inherit pkgs self; };
        default-module = import ./checks/default-module.nix { inherit pkgs self nixpkgs; };
        seed-input = import ./checks/seed-input.nix { inherit pkgs self; };
        seed-guard = import ./checks/seed-guard.nix { inherit pkgs self nixpkgs; };
        lockout-guard = import ./checks/lockout-guard.nix { inherit pkgs self nixpkgs; };
        config-guard = import ./checks/config-guard.nix { inherit pkgs self nixpkgs; };
        no-personal-data = import ./checks/no-personal-data.nix { inherit pkgs; };
        consumable = import ./checks/consumable.nix { inherit pkgs self; };
        mutation = import ./checks/mutation.nix { inherit pkgs self nixpkgs; };
        limits = import ./checks/limits.nix { inherit pkgs self; };
      };
    };
}
