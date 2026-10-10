## DHCP6 client module
## ===================
##
##  This is for use if you have an IPv6-capable upstream that provides
##  address information and/or prefix delegation using DHCP6. It
##  provides a service to request address information in the form of a
##  DHCP lease, and two dependent services that listen for updates
##  to the DHCP address information and can be used to update
##  addresses of network interfaces that you want to assign those
##  prefixes to

{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (pkgs) liminix;
in
{
  imports = [
    ../ipv6-autoconfig
  ];
  options = {
    system.service.dhcp6c = {
      client = mkOption { type = liminix.lib.types.serviceDefn; };
      prefix = mkOption { type = liminix.lib.types.serviceDefn; };
      address = mkOption { type = liminix.lib.types.serviceDefn; };
    };
  };
  config.system.service.dhcp6c = {
    client = config.system.callService ./client.nix {
      interface = mkOption {
        type = liminix.lib.types.interface;
        description = "interface (usually WAN) to query for DHCP6";
      };
      wait-for = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "pathname that must exist before the client is started, for interfaces whose IPv6 is only usable later";
      };
      wait-time = mkOption {
        type = types.int;
        default = 20;
        description = "how long to wait for wait-for, in seconds";
      };
      timeout-up = mkOption {
        type = types.int;
        default = 60 * 1000;
        description = "how long the client has to become ready, in milliseconds";
      };
    };
    address = config.system.callService ./address.nix {
      client = mkOption {
        type = types.anything; # liminix.lib.types.service;
      };
      interface = mkOption {
        type = liminix.lib.types.interface;
        description = "interface to assign the address to";
      };
    };
    prefix = config.system.callService ./prefix.nix {
      client = mkOption {
        type = types.anything; # liminix.lib.types.service;
      };
      interface = mkOption {
        type = liminix.lib.types.interface;
        description = "interface to assign <prefix>::1 to";
      };
    };
  };
}
