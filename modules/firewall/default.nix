## Firewall
## ========
##
## Provides a service to create an nftables ruleset based on
## configuration supplied to it.

{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (pkgs) liminix;

  # The modules the ruleset needs. A composition that already loads modules
  # can merge these names into its own tree and set firewall.kernelModules to
  # that service instead, so that the image has one kmodloader rather than two
  # trees that insmod the same nf_conntrack/nf_nat and ship twice the kernel's
  # modules (ax6600-rootfs.nix does this).
  targets = [
    "nft_fib_ipv4"
    "nft_fib_ipv6"
    "nf_log_syslog"

    "nf_conntrack"
    "nf_defrag_ipv4"
    "nf_defrag_ipv6"
    "nf_log_syslog"
    "nf_nat"
    "nf_reject_ipv4"
    "nf_reject_ipv6"
    "nf_tables"
    "nft_chain_nat"
    "nft_ct"
    "nft_fib"
    "nft_fib_ipv4"
    "nft_fib_ipv6"
    "nft_limit"
    "nft_log"
    "nft_masq"
    "nft_nat"
    "nft_reject"
    "nft_reject_inet"
    "nft_reject_ipv4"
    "nft_reject_ipv6"
  ];

  kmodules = pkgs.kmodloader.override {
    inherit (config.system.outputs) kernel;
    inherit targets;
  };
in
{
  # we use the secrets subscriber to restart when interfaces change
  imports = [ ../secrets ];

  options = {
    system.service.firewall = mkOption {
      type = liminix.lib.types.serviceDefn;
    };
    firewall = {
      kernelModules = mkOption {
        type = types.nullOr liminix.lib.types.service;
        default = null;
        description = ''
          A service that loads firewall.kernelModuleTargets, used as the
          firewall's dependency instead of the kmodloader this module builds
          for itself. Its module tree has to contain those targets.
        '';
      };
      kernelModuleTargets = mkOption {
        type = types.listOf types.str;
        internal = true;
        description = ''
          modprobe names of the modules the ruleset needs, for merging into
          the targets of the service in firewall.kernelModules.
        '';
      };
    };
  };
  config = {
    firewall.kernelModuleTargets = targets;

    system.service.firewall =
      let
        svc = config.system.callService ./service.nix {
          extraRules = mkOption {
            type = types.attrsOf types.attrs;
            description = "firewall ruleset";
            default = { };
          };
          zones = mkOption {
            type = types.attrsOf (types.listOf liminix.lib.types.service);
            default = { };
            example = lib.literalExpression ''
              {
                lan = with config.hardware.networkInterfaces; [ int ];
                wan = [ config.services.ppp0 ];
              }
            '';
          };
          rules = mkOption {
            type = types.attrsOf types.attrs; # we could usefully tighten this a bit :-)
            default = import ./default-rules.nix;
            description = "firewall ruleset";
          };
        };

        # the composition's tree when it has one, else the private tree above.
        # Laziness is what keeps an unset option from building that tree.
        moduleService =
          if config.firewall.kernelModules == null then kmodules else config.firewall.kernelModules;
      in
      svc
      // {
        build =
          args:
          let
            args' = args // {
              dependencies = (args.dependencies or [ ]) ++ [ moduleService ];
            };
          in
          svc.build args';
      };
    programs.busybox.applets = [
      "insmod"
      "rmmod"
    ];
    kernel.config = {
      NETFILTER = "y";
      NETFILTER_ADVANCED = "y";
      NF_CONNTRACK = "m";

      NETLINK_DIAG = "y";

      NFT_CT = "m";
      NFT_FIB_IPV4 = "m";
      NFT_FIB_IPV6 = "m";
      NFT_LIMIT = "m";
      NFT_LOG = "m";
      NFT_MASQ = "m";
      NFT_NAT = "m";
      NFT_REJECT = "m";
      NFT_REJECT_INET = "m";

      NF_CT_PROTO_SCTP = "y";
      NF_CT_PROTO_UDPLITE = "y";
      NF_LOG_SYSLOG = "m";
      NF_NAT = "m";
      NF_NAT_MASQUERADE = "y";
      NF_TABLES = "m";
      NF_TABLES_INET = "y";
      NF_TABLES_IPV4 = "y";
      NF_TABLES_IPV6 = "y";
    };
  };
}
