{ lamacloud, ... }: lamacloud.mkLamaCloudVM (pkgs: {
  config-root = ./.;
  target-arch = "x86_64-linux";
  hostName = "lc-ci-fixture";

  # Intentionally minimal: the fixture exists solely to prove the end-to-end
  # build/deploy machinery works. NEVER add production packages here.
  packages = with pkgs; [
    hello
  ];

  # Marker file - the e2e test asserts this content after `colmena apply`.
  # Updating CI_FIXTURE_MARKER below forces a deploy change, which is what
  # the assertion looks for. Do NOT remove without updating the assertion.
  environment.etc."lamacloud-ci-marker" = {
    text = "deployed-via-colmena\n";
    mode = "0644";
  };

  # The bootstrap VM (tests/fixtures/vm-target.nix) brings its own
  # bootloader, partition layout and fileSystems via `qemu-vm.nix`. The
  # configuration in THIS file is the closure that Colmena DEPLOYS onto
  # that already-booted VM -- never installed to a fresh disk. We therefore:
  #
  #   1. Declare a stub `fileSystems."/"` so the NixOS top-level assertion
  #      passes during evaluation. The activation script doesn't remount /
  #      so the device value is irrelevant at runtime.
  #
  #   2. Disable the bootloader from foundation.nix (systemd-boot) and
  #      stub out `system.build.installBootLoader` so `nixos-rebuild switch`
  #      doesn't try to mount /boot or write to EFI variables on the
  #      transient QEMU image.
  #
  # If you remove this fixture, also delete these overrides and partition
  # planning workflow (`lamacloud part`) becomes the canonical path again.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  boot.loader.systemd-boot.enable = pkgs.lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = pkgs.lib.mkForce false;
  boot.loader.grub.enable = false;

  system.build.installBootLoader = pkgs.writeShellScript "lc-ci-fixture-no-bootloader" ''
    echo "[lc-ci-fixture] bootloader install intentionally skipped"
  '';

  networking.useDHCP = true;
  networking.firewall.enable = false;
})
