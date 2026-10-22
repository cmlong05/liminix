{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (pkgs) liminix;
in
{
  options.system.service.singBox = mkOption {
    type = liminix.lib.types.serviceDefn;
  };

  config = {
    kernel.config.TUN = "y";

    system.service.singBox = config.system.callService ./service.nix {
      configFile = mkOption {
        type = types.str;
        default = "/var/lib/liminix/sing-box/config.json";
      };
      templateFile = mkOption {
        type = types.path;
      };
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
    };
  };
}
