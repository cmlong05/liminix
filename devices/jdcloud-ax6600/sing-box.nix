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
  template = pkgs.writeText "sing-box-config.template.json" (
    import "${modulesPath}/sing-box/config.nix" {
      inherit (cfg) tunName;
      proxyRuleFile = "${cfg.stateDir}/proxy.json";
      bypassRuleFile = "${cfg.stateDir}/bypass.json";
    }
  );
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
    routingMark = mkOption {
      type = types.ints.unsigned;
      default = 9011;
    };
    routingTable = mkOption {
      type = types.ints.positive;
      default = 233;
    };
    routingRulePriority = mkOption {
      type = types.ints.between 1 32765;
      default = 18000;
    };
    policyRoutingRules = mkOption {
      type = types.attrsOf types.attrs;
      readOnly = true;
    };
  };

  config = {
    defaultProfile.packages = [ pkgs.sing-box ];

    services.sing-box = config.system.service.singBox.build {
      configFile = "${cfg.stateDir}/config.json";
      templateFile = template;
      inherit (cfg)
        stateDir
        tunName
        routingMark
        routingTable
        routingRulePriority
        ;
    };

    firewall.appendRules = {
      input-ip4-lan = [
        "tcp dport 1080 accept"
        "udp dport 1080 accept"
        "tcp dport 1081 accept"
        "udp dport 1081 accept"
      ];
      input-ip6-lan = [
        "tcp dport 1080 accept"
        "udp dport 1080 accept"
        "tcp dport 1081 accept"
        "udp dport 1081 accept"
      ];
      forward-ip4-modules = [
        "iifname @lan oifname \"${cfg.tunName}\" accept"
        "iifname \"${cfg.tunName}\" oifname @lan accept"
      ];
      forward-ip6-modules = [
        "iifname @lan oifname \"${cfg.tunName}\" accept"
        "iifname \"${cfg.tunName}\" oifname @lan accept"
      ];
    };

    filesystem = dir {
      etc = dir {
        "sing-box" = dir {
          "config.json.template" = symlink "${template}";
        };
      };
    };

    jdcloudAx6600.singBox = {
      # WAN 出向在 prerouting 标记；FIB 判断避免 LAN 互访进入 TUN。
      policyRoutingRules = {
        sing-box-mark-ip4 = {
          type = "filter";
          family = "ip";
          hook = "prerouting";
          priority = "mangle";
          policy = "accept";
          rules = [
            "iifname @lan fib daddr oifname @wan meta mark set ${toString cfg.routingMark}"
          ];
        };
        sing-box-mark-ip6 = {
          type = "filter";
          family = "ip6";
          hook = "prerouting";
          priority = "mangle";
          policy = "accept";
          rules = [
            "iifname @lan fib daddr oifname @wan meta mark set ${toString cfg.routingMark}"
          ];
        };
      };
    };
  };
}
