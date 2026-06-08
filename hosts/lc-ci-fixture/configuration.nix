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

  # Allow `sayo` (used by Colmena) to NOPASSWD sudo, already covered by
  # foundation.nix wheel rule. Nothing extra needed.

  # The bootstrap VM brings its own bootloader / fileSystems config, so we
  # OMIT a partition.json for this host. mkLamaCloudVM tolerates that and
  # leaves disko disabled.
  networking.useDHCP = true;
  networking.firewall.enable = false;
})
