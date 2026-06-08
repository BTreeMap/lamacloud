{ lamacloud, ... }: lamacloud.mkLamaCloudVM (pkgs: {
  config-root = ./.;
  target-arch = "aarch64-linux";
  hostName = "lc-entrypoint-hk01";
  
  packages = with pkgs; [
    serverctl
    nodejs nginx certbot
    ethtool
  ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="en*|eth*", RUN+="${pkgs.ethtool}/bin/ethtool -K %k rx-udp-gro-forwarding on rx-gro-list off"
  '';

  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.rmem_max" = 7500000;
    "net.core.wmem_max" = 7500000;
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose"; 
  };

  services.tailscale = {
    enable = true;
    port = 41641;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraSetFlags = [
      "--ssh"
      "--advertise-exit-node"
      "--webclient"
    ];
  };
})
