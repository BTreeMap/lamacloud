# Standalone NixOS module describing the bootstrap VM that Colmena targets
# during the e2e-deploy workflow. This VM is intentionally *minimal*: just
# enough NixOS to accept an SSH connection from the sayo fixture key and
# allow `nixos-rebuild switch` to run via sudo.
#
# DO NOT confuse this with `hosts/lc-ci-fixture/configuration.nix` -- that
# is the config Colmena DEPLOYS. This is the config the VM *boots* with.
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    # Adds virtualisation.qemu.options, fileSystems, bootloader, etc.
    "${modulesPath}/virtualisation/qemu-vm.nix"
  ];

  # Enough disk + RAM to land an entire NixOS closure during deploy.
  virtualisation = {
    memorySize = 2048;
    cores = 2;
    diskSize = 8192;
    graphics = false;

    # Port-forward the guest sshd to host:2222. The fixture lamacloud.json
    # points lc-ci-fixture -> 127.0.0.1:2222 so the runner can connect.
    forwardPorts = [
      { from = "host"; host.port = 2222; guest.port = 22; }
    ];
  };

  networking.hostName = "lc-ci-fixture";
  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.sayo = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHB+9o3584ku+1BbOqZPsMDhyN6E0nPLbus6vVV30j2v sayo@lamacloud-ci-fixture"
    ];
  };

  # NOPASSWD sudo so Colmena can `sudo nixos-rebuild switch` as sayo.
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  # Flakes + nix-command so the deployed closure activation works.
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "sayo" ];
  };

  # The deployed lc-ci-fixture writes /etc/lamacloud-ci-marker; we leave
  # nothing here in /etc that would shadow it.

  system.stateVersion = "25.11";
}
