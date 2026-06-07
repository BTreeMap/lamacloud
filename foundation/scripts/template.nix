{ lamacloud, ... }: lamacloud.mkLamaCloudVM (pkgs: {
  config-root = ./.;
  target-arch = "TEMPLATE_ARCH";
  hostName = "TEMPLATE_HOSTNAME";
  
  packages = with pkgs; [
  ];
})
