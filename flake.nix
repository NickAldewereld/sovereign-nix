{
  description = "Secure, sovereign NixOS modules — every machine unique, every boot clean, every line auditable";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    hostSeed = {
      url = "path:./example-seed";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      hostSeed,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      seed = nixpkgs.lib.removeSuffix "\n" (builtins.readFile "${hostSeed}/seed");
    in
    {
      nixosModules = {
        harden = ./modules/harden.nix;
        diversity = ./modules/diversity.nix;
        impermanence = ./modules/impermanence.nix;
        sovereign = ./modules/sovereign.nix;

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
          ./profiles/laptop.nix
          ./hosts/example
          # CI only: lets `nix flake check` evaluate this host on the checked-in
          # sentinel seed. DELETE this when you copy the host — without it the
          # assertion in modules/diversity.nix stops the build.
          { sovereign.diversity.allowExampleSeed = true; }
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
        no-personal-data = import ./checks/no-personal-data.nix { inherit pkgs; };
      };
    };
}
