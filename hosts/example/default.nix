{
  pkgs,
  seed,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./filesystems.nix
  ];

  networking.hostName = "example";
  time.timeZone = "Europe/Amsterdam";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "nl_NL.UTF-8";
    LC_MONETARY = "nl_NL.UTF-8";
  };
  console.keyMap = "us";

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb.layout = "us";

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  nixpkgs.config.allowUnfree = true;

  # The seed arrives as a flake input. Real machines override it at rebuild
  # time; see the nrs/nrt aliases. No --impure anywhere.
  sovereign.diversity.seed = seed;

  sovereign.impermanence = {
    device = "/dev/mapper/cryptroot";
    persistPaths = [
      "/etc/NetworkManager/system-connections"
      "/etc/sovereign"
      "/var/lib/nixos"
      "/var/lib/tailscale"
      "/var/lib/bluetooth"
      "/var/lib/docker"
      "/var/log"
    ];
  };

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.firewall.allowedUDPPorts = [ 41641 ];

  # docker_28 (the default in this nixpkgs pin) is marked insecure
  # (unmaintained since Nov 2025); pin docker_29 instead.
  virtualisation.docker.enable = true;
  virtualisation.docker.package = pkgs.docker_29;

  users.users.example = {
    isNormalUser = true;
    description = "Example user";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];
    # Generate with `mkpasswd -m sha-512` and place it on the machine, outside
    # the repository. Impermanence persists /persist across boots.
    hashedPasswordFile = "/persist/etc/sovereign/example.passwd";
    # Add your own public keys here.
    openssh.authorizedKeys.keys = [ ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    curl
    wget
    tree
    unzip
    ripgrep
    fd
    jq
    nmap
    dig
    whois
    wireguard-tools
    gnupg
    age
    sops
    python3
    brightnessctl
    powertop
    usbutils
    pciutils
    lshw
    rsync
  ];
  programs.fuse.userAllowOther = true;

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    fira-code
    jetbrains-mono
  ];

  environment.shellAliases = {
    # seed.d holds the seed and nothing else: --override-input copies the whole
    # directory into the world-readable store, so hashedPasswordFile and
    # friends must not live in it.
    nrs = "sudo nixos-rebuild switch --flake /etc/nixos#example --override-input hostSeed path:/persist/etc/sovereign/seed.d";
    nrt = "sudo nixos-rebuild test --flake /etc/nixos#example --override-input hostSeed path:/persist/etc/sovereign/seed.d";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.stateVersion = "25.11";
}
