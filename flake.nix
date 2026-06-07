{
  description = "Lamacloud Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/26.05";
    disko = { url = "github:nix-community/disko/latest"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = { nixpkgs, disko, ... }: 
    with nixpkgs.lib;
    let
      hosts = builtins.attrNames (builtins.readDir ./hosts); 
      lamacloud = import ./foundation/lamacloud.nix { inherit nixpkgs; inherit disko; };
    in {
      nixosConfigurations = genAttrs hosts (hostName: import (./hosts + /${hostName}/configuration.nix) { 
        inherit nixpkgs; 
        inherit lamacloud;
      } ); 
    };
}
