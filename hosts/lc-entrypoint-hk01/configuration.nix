{ lamacloud, ... }: lamacloud.mkLamaCloudVM (pkgs: {
  config-root = ./.;
  target-arch = "aarch64-linux";
  hostName = "lc-entrypoint-hk01";
  
  packages = with pkgs; [
    serverctl
    nodejs nginx certbot
  ];

  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.rmem_max" = 7500000;
    "net.core.wmem_max" = 7500000;
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
})
