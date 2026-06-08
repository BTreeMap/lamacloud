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
    # Bind explicitly to 127.0.0.1 on the host so the forward never clashes
    # with anything else bound on 0.0.0.0:2222.
    forwardPorts = [
      { from = "host"; host.address = "127.0.0.1"; host.port = 2222; guest.port = 22; }
    ];
  };

  networking.hostName = "lc-ci-fixture";
  # Firewall disabled belt-and-suspenders; openssh.openFirewall also set
  # so that re-enabling the firewall later doesn't silently break SSH.
  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    # Explicit listen address removes any ambiguity about IPv6-only binding
    # behaviour that could prevent QEMU usermode forwarding from reaching us.
    listenAddresses = [
      { addr = "0.0.0.0"; port = 22; }
    ];
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

  # Definitive readiness marker.
  #
  # The host-side `deploy-vm.sh` tails the VM serial log for the exact
  # token below. When seen, sshd is guaranteed to be accepting connections.
  # This eliminates the previous race between "sshd has started" (which
  # systemd reports as soon as the unit is forked) and "sshd is actually
  # listening on port 22" (which can lag by a couple of seconds).
  systemd.services.lc-ci-ready = {
    description = "Emit lc-ci-fixture VM readiness marker";
    wantedBy = [ "multi-user.target" ];
    after = [ "sshd.service" "network-online.target" ];
    requires = [ "sshd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Poll until sshd actually accepts a TCP connection before emitting.
      ExecStart = pkgs.writeShellScript "lc-ci-ready" ''
        set -eu
        for _ in $(seq 1 60); do
          if ${pkgs.iproute2}/bin/ss -tln 'sport = :22' | ${pkgs.gnugrep}/bin/grep -q ':22'; then
            echo "===LC_CI_VM_SSH_READY===" >/dev/console
            echo "===LC_CI_VM_SSH_READY===" >/dev/ttyS0 2>/dev/null || true
            exit 0
          fi
          sleep 1
        done
        echo "===LC_CI_VM_SSH_FAILED===" >/dev/console
        exit 1
      '';
    };
  };

  system.stateVersion = "25.11";
}
