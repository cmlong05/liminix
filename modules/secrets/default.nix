## Secrets

## various ways to manage secrets without writing them to the
## nix store

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
  options.system.service.secrets = {
    local = mkOption {
      description = "read secrets from a JSON file on the running system";
      type = liminix.lib.types.serviceDefn;
    };
    outboard = mkOption {
      description = "fetch secrets from external vault with https";
      type = liminix.lib.types.serviceDefn;
    };
    tang = mkOption {
      description = "fetch secrets from encrypted local pathname, using tang";
      type = liminix.lib.types.serviceDefn;
    };
    subscriber = mkOption {
      description = "wrapper around a service that needs notifying (e.g. restarting) when secrets change";
      type = liminix.lib.types.serviceDefn;
    };

  };
  config.system.service.secrets = {
    local = config.system.callService ./local.nix {
      name = mkOption {
        description = "service name";
        type = types.str;
      };
      path = mkOption {
        description = "pathname of the JSON file to read";
        type = types.str;
      };
      seed = mkOption {
        description = ''
          JSON file to publish while `path` is not on a mounted filesystem,
          and to copy to `path` on the first run that finds one.
        '';
        type = types.nullOr types.path;
        default = null;
      };
      interval = mkOption {
        description = "how often to re-read the file, in minutes";
        type = types.int;
        default = 1;
      };
    };
    outboard = config.system.callService ./outboard.nix {
      url = mkOption {
        description = "source url";
        type = types.strMatching "https?://.*";
      };
      username = mkOption {
        description = "username for HTTP basic auth";
        type = types.nullOr types.str;
      };
      password = mkOption {
        description = "password for HTTP basic auth";
        type = types.nullOr types.str;
      };
      tlsCertificate = mkOption {
        description = "client certificate to present for mTLS";
        type = types.nullOr types.path;
      };
      tlsCaCertificate = mkOption {
        description = "CA certificate";
        type = types.nullOr types.path;
      };
      tlsPrivateKey = mkOption {
        description = "client private key to use for mTLS";
        type = types.nullOr types.path;
      };
      name = mkOption {
        description = "service name";
        type = types.str;
      };
      interval = mkOption {
        type = types.int;
        default = 30;
        description = "how often to check the source, in minutes";
      };
    };
    tang = config.system.callService ./tang.nix {
      path = mkOption {
        description = "encrypted source pathname";
        type = types.path;
      };
      name = mkOption {
        description = "service name";
        type = types.str;
      };
      interval = mkOption {
        type = types.int;
        default = 30;
        description = "how often to check the source, in minutes";
      };
    };
    subscriber = config.system.callService ./subscriber.nix {
      watch = mkOption {
        description = "secrets paths to subscribe to";
        type = types.listOf (types.functionTo types.anything);
      };
      service = mkOption {
        description = "subscribing service that will receive notification";
        type = liminix.lib.types.service;
      };
      action = mkOption {
        description = "how do we notify the service to regenerate its config";
        default = "restart-all";
        type = types.enum [
          "restart"
          "restart-all"
          "hup"
          "int"
          "quit"
          "kill"
          "term"
          "winch"
          "usr1"
          "usr2"
        ];
      };
    };
  };
}
