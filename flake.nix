{
  description = "Lamacloud Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/26.05";
    disko = { url = "github:nix-community/disko/latest"; inputs.nixpkgs.follows = "nixpkgs"; };
    colmena = { url = "github:zhaofengli/colmena"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = { self, nixpkgs, disko, colmena, ... }:
    with nixpkgs.lib;
    let
      hosts = builtins.attrNames (builtins.readDir ./hosts);
      lamacloud = import ./foundation/lamacloud.nix { inherit nixpkgs disko; };

      # Single source of truth: load every host's spec once. Both
      # nixosConfigurations and colmenaHive are derived from these.
      specs = genAttrs hosts (hostName:
        import (./hosts + "/${hostName}/configuration.nix") {
          inherit nixpkgs lamacloud;
        });

      remotes =
        let f = ./lamacloud.json; in
        if builtins.pathExists f then
          (builtins.fromJSON (builtins.readFile f)).remotes or {}
        else {};

      # Tolerate string-or-int ports (legacy lamacloud.json stores strings).
      parsePort = p:
        if p == null then 22
        else if builtins.isInt p then p
        else if builtins.isString p then
          (if p == "" then 22 else lib.toInt p)
        else 22;

      mkColmenaNode = hostName: spec: { lib, ... }: let
        remote = remotes.${hostName} or null;
      in {
        # Re-use the exact module list backing the spec. This guarantees
        # Colmena and `nixos-rebuild build` produce identical store paths.
        imports = spec.modules;

        deployment = {
          targetHost =
            if remote != null && (remote.host or null) != null
            then remote.host
            else hostName;
          targetPort = parsePort (if remote != null then remote.port or null else null);
          # NOTE: foundation.nix forces PermitRootLogin=no, so default to
          # the CI user `sayo` and let Colmena escalate via sudo.
          targetUser =
            if remote != null && (remote.user or null) != null
            then remote.user
            else "sayo";
          tags = [ "lamacloud" ];
          replaceUnknownProfiles = true;
        };
      };
    in {
      # Legacy build path: `nixos-rebuild build --flake .#<host>`.
      nixosConfigurations = mapAttrs (_: spec: lamacloud.evalSpec spec) specs;

      # Deployment path: `colmena build/apply`.
      colmenaHive = colmena.lib.makeHive ({
        meta = {
          # Evaluation-host nixpkgs (the runner / local machine).
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
          nodeNixpkgs = mapAttrs (_: spec: spec.pkgs) specs;
        };
      } // mapAttrs mkColmenaNode specs);

      # E2E test target VM. NOT a production output - exists only so the
      # GitHub Actions e2e-deploy workflow can boot a throwaway NixOS VM
      # via QEMU and exercise the full Colmena deploy pipeline against it.
      # See tests/fixtures/vm-target.nix and tests/README.md.
      packages.x86_64-linux.ci-target-vm =
        (nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./tests/fixtures/vm-target.nix ];
        }).config.system.build.vm;

      # Re-export the Colmena binary from our pinned input so CI installs
      # the EXACT same version that produced our colmenaHive output.
      # Prevents version skew between hive evaluation and the deploy tool.
      packages.x86_64-linux.colmena = colmena.packages.x86_64-linux.colmena;
    };
}
