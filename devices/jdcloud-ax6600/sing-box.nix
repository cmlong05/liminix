{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (pkgs.pseudofile) dir symlink;

  cfg = config.jdcloudAx6600.singBox;
  template = ./sing-box/config_temp.json;
in
{
  imports = [ "${modulesPath}/sing-box" ];

  options.jdcloudAx6600.singBox = {
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/liminix/sing-box";
    };
    tunName = mkOption {
      type = types.str;
      default = "sing-box0";
    };
  };

  config = {
    defaultProfile.packages = [ pkgs.sing-box ];

    kernel.config = {
      NETFILTER_NETLINK_QUEUE = "m";
      NFT_QUEUE = "m";
      NFT_REDIR = "m";
    };

    firewall.kernelModuleTargets = [
      "nfnetlink_queue"
      "nft_queue"
      "nft_redir"
    ];

    services.sing-box = config.system.service.singBox.build {
      configFile = "${cfg.stateDir}/config.json";
      inherit (cfg)
        stateDir
        tunName
        ;
    };

    firewall.appendRules = {
      input-ip4-lan = [
        "tcp dport 1080 accept"
        "udp dport 1080 accept"
        "tcp dport 1081 accept"
        "udp dport 1081 accept"
        "ct status dnat accept"
      ];
      input-ip6-lan = [
        "tcp dport 1080 accept"
        "udp dport 1080 accept"
        "tcp dport 1081 accept"
        "udp dport 1081 accept"
        "ct status dnat accept"
      ];
      forward-ip4-modules = [
        "iifname @lan oifname \"${cfg.tunName}\" accept"
        "iifname \"${cfg.tunName}\" oifname @lan accept"
      ];
      forward-ip6-modules = [
        "iifname @lan oifname \"${cfg.tunName}\" accept"
        "iifname \"${cfg.tunName}\" oifname @lan accept"
      ];
      input-ip4-modules = [
        "iifname \"${cfg.tunName}\" accept"
        "oifname \"${cfg.tunName}\" accept"
      ];
      input-ip6-modules = [
        "iifname \"${cfg.tunName}\" accept"
        "oifname \"${cfg.tunName}\" accept"
      ];
    };

    filesystem = dir {
      etc = dir {
        "sing-box" = dir {
          "config.json.template" = symlink "${template}";
        };
        "ssl" = dir {
          "certs" = dir {
            "ca-certificates.crt" = symlink "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          };
        };
      };
    };

  };
}
