({ nixpkgs, disko, ... }: let
  aliasFactory = import ./alias.nix { inherit nixpkgs; };
  lib = nixpkgs.lib;
in
rec {
  flattenAttrSet = set: join:
    with builtins;
    let
      allKeys = builtins.attrNames set;
      isNested = key: builtins.typeOf (builtins.getAttr key set) == "set";

      nestedElements = builtins.filter isNested allKeys;
      pureElements = builtins.attrNames (builtins.removeAttrs set nestedElements);
    in
      lib.attrsets.mergeAttrsList [
        ( lib.genAttrs       (map (it: join + it) pureElements) (it: it) )
        ( lib.mergeAttrsList (map (it: flattenAttrSet (getAttr it set) "${join}${it}/") nestedElements) )
      ];

  readDirRecursive = path: builtins.mapAttrs (file: type:
      if type == "directory" then
        (readDirRecursive "${path}/${file}")
      else file
    ) (builtins.readDir path);

  listFileRecursiveRel = path: rel: builtins.attrNames (flattenAttrSet (readDirRecursive path) rel);
  listFileRecursive = path: listFileRecursiveRel path "";

  mkFileMountsEtc = path: lib.genAttrs (listFileRecursive path) (it: {
    text = builtins.readFile ((builtins.toString path) + "/" + it);
  });

  # mkLamaCloudVM :: (pkgs -> attrset) -> spec
  #
  # Returns a *spec* describing the host. The flake materialises specs into
  # both `nixosConfigurations.<name>` (via `nixpkgs.lib.nixosSystem`) and
  # `colmenaHive` nodes. Hosts therefore have ONE source of truth and the
  # two output paths cannot drift.
  #
  # Spec shape:
  #   { hostName    :: string
  #   , system      :: string         # e.g. "x86_64-linux"
  #   , pkgs        :: nixpkgs        # initialised with overlays
  #   , modules     :: [module]       # ready to feed nixosSystem / Colmena
  #   }
  mkLamaCloudVM = confFactory: let
    probe = confFactory null;
    system = probe.target-arch or "x86_64-linux";

    pkgs = import nixpkgs {
      overlays = [ (import ../packages) ];
      inherit system;
      config = {
        allowUnfree = true;
      };
    };
    conf = confFactory pkgs;

    hostFile = path: "${conf.config-root}/${path}";
    readJSON = path: builtins.fromJSON (builtins.readFile path);
    etcFolder = hostFile "files/etc";

    applyEtcMapping = { ... }: {
      environment = {
        etc = if builtins.pathExists etcFolder then
                mkFileMountsEtc etcFolder
              else {};
      };
    };

    applyCreds = { ... }:
      if !builtins.pathExists (hostFile "creds.json") then
        throw "Missing credentials for '${conf.hostName}'! Generate with 'lamacloud creds new ${conf.hostName}'"
      else if !builtins.pathExists ../sayo.json then
        throw "Missing CI credentials! Generate with 'lamacloud creds new --sayo'"
      else let
        elaina = readJSON (hostFile "creds.json");
        sayo = readJSON ../sayo.json;
      in {
        users.users.elaina.hashedPassword = elaina.elaina.hashedPassword;
        users.users.elaina.openssh.authorizedKeys = elaina.elaina.publicKey;

        users.users.sayo.hashedPassword = sayo.hashedPassword;
        users.users.sayo.openssh.authorizedKeys = sayo.publicKey;
      };

    # partition.json is now OPTIONAL. Hosts without one skip disko entirely
    # (useful for VM-deployable test fixtures and bare-metal hosts whose
    # disk layout is already final). Hosts that DO ship a partition.json
    # continue to feed disko exactly as before.
    applyParts = { ... }:
      if !builtins.pathExists (hostFile "partition.json") then
        { disko.enableConfig = false; }
      else let
        json = readJSON (hostFile "partition.json");
      in {
        disko.enableConfig = true;
        disko.devices.disk = pkgs.lib.genAttrs (builtins.attrNames json) (it:
          let
            disk = builtins.getAttr it json;
          in {
            device = it;
            type = "disk";
            content = {
              type = "gpt";
              partitions = pkgs.lib.genAttrs (builtins.attrNames disk) (partName:
                let
                  part = builtins.getAttr partName disk;
                in
                  if part.role == "rootfs" then
                    {
                      size = part.size;
                      content = {
                        type = "filesystem";
                        format = part.type;
                        mountpoint = "/";
                      };
                    }
                  else if part.role == "boot" then
                    {
                      type = "EF00";
                      size = part.size;
                      content = {
                        type = "filesystem";
                        format = part.type;
                        mountpoint = "/boot";
                        mountOptions = [ "umask=0077" ];
                      };
                    }
                  else if part.role == "swap" then
                    {
                      size = part.size;
                      content = {
                        type = "swap";
                        discardPolicy = "both";
                        resumeDevice = true;
                      };
                    }
                  else if part.role == "mount" then
                    {
                      size = part.size;
                      content = {
                        type = "filesystem";
                        format = part.type;
                        mountpoint = part.mount;
                      };
                    }
                  else
                  throw "Unsupported partition role '${part.role}'! lamacloud.nix is out-of-date!"
              );
            };
          });
      };

    modules = [
      ./foundation.nix

      applyEtcMapping
      applyCreds
      applyParts

      disko.nixosModules.disko

      (aliasFactory.apply (builtins.removeAttrs conf [ "target-arch" ]))
    ];
  in {
    inherit (conf) hostName;
    inherit system pkgs modules;
  };

  # Build a `nixpkgs.lib.nixosSystem` from a spec returned by `mkLamaCloudVM`.
  # Kept as a separate function so callers (flake.nix, nix-debug) share logic.
  evalSpec = spec: nixpkgs.lib.nixosSystem {
    inherit (spec) system modules;
  };
})
