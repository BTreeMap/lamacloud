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
