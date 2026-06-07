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
        # We first process the part with attributes
        ( lib.genAttrs       (map (it: join + it) pureElements) (it: it) ) 
        # Then we process the part that requires recursion
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

  mkLamaCloudVM = confFactory: let 
    probe = confFactory null;
    pkgs = import nixpkgs {
      overlays = [ (import ../packages) ];
      system = probe.target-arch;
      config = {
        allowUnfree = true;
      };
    };
    conf = confFactory pkgs;

    hostFile = path: "${conf.config-root}/${path}";
    readJSON = path: builtins.fromJSON (builtins.readFile path );
    etcFolder = hostFile "files/etc";

    applyEtcMapping = { pkgs, ... }: {
      environment = {
        etc = if builtins.pathExists etcFolder then 
                mkFileMountsEtc etcFolder 
              else {};
      };
    };

    applyCreds = { pkgs, ... }: 
      if !builtins.pathExists (hostFile "creds.json") then
        throw "Missing credentials! Generate with 'lamacloud creds new ${conf.hostName}'"
      else if !builtins.pathExists ../sayo.json then
        throw "Missing CI Credentials! Generate with 'lamacloud creds new --sayo'"
      else let
        elaina = readJSON (hostFile "creds.json");
        sayo = readJSON ../sayo.json; # Global CI Credentials
      in {
        users.users.elaina.hashedPassword = elaina.elaina.hashedPassword;
        users.users.elaina.openssh.authorizedKeys = elaina.elaina.publicKey;

        users.users.sayo.hashedPassword = sayo.hashedPassword;
        users.users.sayo.openssh.authorizedKeys = sayo.publicKey;
      };

    applyParts = { pkgs, ... }:
      if !builtins.pathExists (hostFile "partition.json") then
        throw "Missing partition file! Generate with 'lamacloud part ${conf.hostName}'"
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
                  throw "Unsupported partition role! lamacloud.nix is out-of-date!"
              );
            };
          }); 
      };

  in nixpkgs.lib.nixosSystem {
    system = conf.target-arch or "x86_64-linux";

    modules = [
      # Server base template
      ./foundation.nix

      # Apply generated config
      applyEtcMapping
      applyCreds
      applyParts
     
      disko.nixosModules.disko

      # Make actual config from abbr version
      (aliasFactory.apply (builtins.removeAttrs conf ["target-arch"]))
    ];
  };
}) 
