{ pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  users = {
    users = {
      elaina = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
      };

      sayo = {
        isNormalUser = true;
        createHome = false;

        extraGroups = [ "wheel" ];
      };
    };
  };

  security.sudo = {
    wheelNeedsPassword = false; 
  };

  environment = {
    systemPackages = with pkgs; [
      # Essential packages
      openssh git neovim gnupg networkmanager
      python315 htop wget curl
      dnsutils iputils unzip zip p7zip lsof
      gnugrep perl gnused
    ];

    variables = {
      EDITOR = "nvim";
    };
  };

  services = {
    openssh = {
      enable = true;
      # Open port 22 in the firewall. Without this, hosts that keep the
      # default-enabled NixOS firewall would be unreachable over SSH and
      # Colmena (CI *and* deploy-prod.yml) could never connect.
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      # Colmena copies locally-built (unsigned) closures to each host through
      # the nix-daemon. The deploy user must be trusted or the daemon rejects
      # the paths with "cannot add path ... lacks a signature". `sayo` is the
      # deploy identity used by both CI and deploy-prod.yml.
      trusted-users = [ "root" "sayo" ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "25.11";
}
