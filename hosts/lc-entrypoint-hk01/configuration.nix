{ lamacloud, ... }: lamacloud.mkLamaCloudVM (pkgs: {
  config-root = ./.;
  target-arch = "aarch64-linux";
  hostName = "lc-entrypoint-hk01";
  
  packages = with pkgs; [
    serverctl
    nodejs nginx certbot
  ];
})
