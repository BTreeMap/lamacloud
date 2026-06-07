{ nixpkgs, ... }:
let 
  optional = val: nixpkgs.lib.mkIf (val != null) val;
  required = val: assert val != null; val;
  remove-list = [ "config-root" "hostName" "motd" "packages" "env" ];
  remove-attr = set: builtins.removeAttrs set remove-list;
in {
  apply = conf: remove-attr (nixpkgs.lib.recursiveUpdate conf {
    networking.hostName = required (conf.hostName or null);
    users.motd = optional (conf.motd or null);
    environment.systemPackages = optional (conf.packages or null);
    environment.variables = optional (conf.env or null);
  });
}
