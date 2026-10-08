## Tailscale
## =========
##
## WireGuard-based mesh VPN. Provides the tailscaled daemon and, only if
## an auth key is supplied, a one-shot login at boot: without one the
## first `tailscale up` is run by hand on the running system, and the
## node state that keeps that login alive lives under stateDir.

{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (pkgs) liminix;
  inherit (pkgs.pseudofile) dir symlink;
in
{
  options.system.service.tailscale = mkOption {
    type = liminix.lib.types.serviceDefn;
  };

  config = lib.mkMerge [
    {
      # tailscaled creates tailscale0 through /dev/net/tun
      kernel.config.TUN = "y";

      # tailscaled cannot be driven from a shell without it; the list is
      # a listOf, so this appends to whatever the composition sets
      defaultProfile.packages = [ pkgs.tailscale ];

      # tailscale and tailscaled both default to
      # /var/run/tailscale/tailscaled.sock; /var/run pointing at /run is
      # what lets them agree on a root that is read-only apart from /run
      filesystem = dir {
        var = dir {
          run = symlink "/run";
        };
      };

      system.service.tailscale = config.system.callService ./service.nix {
        name = mkOption {
          type = types.str;
          default = "tailscale";
        };
        tunMode = mkOption {
          type = types.enum [
            "kernel"
            "userspace"
          ];
          default = "kernel";
          description = ''
            "kernel" gives tailscaled its own tailscale0 interface through
            the TUN driver, which is what subnet routes and direct access
            to tailnet addresses need. "userspace" keeps everything in the
            daemon and only offers a SOCKS5/HTTP proxy to local processes.
          '';
        };
        stateDir = mkOption {
          type = types.path;
          default = "/persist/tailscale";
          description = "where the node key and the rest of tailscaled's state live";
        };
        socket = mkOption {
          type = types.path;
          default = "/var/run/tailscale/tailscaled.sock";
        };
        authKey = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Tailscale auth key used for a login at boot. The value is
            written into the nix store and therefore into the image, so
            leaving it null and logging in by hand is usually the better
            trade.
          '';
        };
        upArgs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "extra arguments for tailscale up";
        };
      };
    }
    (lib.mkIf (config ? firewall) {
      # the firewall's default chains jump to these (see modules/firewall
      # /default-rules.nix), so importing this module is what brings the
      # rules in - and not importing it takes them out again
      firewall.appendRules = {
        input-ip4-modules = [
          "iifname \"tailscale0\" ip saddr 100.64.0.0/10 accept"
        ];
        forward-ip4-modules = [
          "iifname \"tailscale0\" ip saddr 100.64.0.0/10 accept"
          "oifname \"tailscale0\" accept"
        ];
      };
    })
  ];
}
