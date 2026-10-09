{
  stdenvNoCC,
  s6,
  lib,
  writeScript,
  serviceFns,
}:
let
  prefix = "/run/services/outputs";
  output = service: name: "${prefix}/${service.name}/${name}";
  inherit (lib.attrsets) mapAttrsRecursive collect;
  inherit (lib.strings) concatStringsSep;
  # The shell must exec the service command itself, or s6-supervise
  # supervises a sh: a down then kills only the sh and the service keeps
  # running as an orphan that still owns its listening sockets (dnsmasq
  # never rebinds, every restart leaks another process). busybox ash only
  # execs the last command of a `-c` string, never that of a script file,
  # and only when the string ends right after the command - hence the
  # trailing-whitespace strip.
  trimRight =
    s:
    if s == "" then
      ""
    else if
      lib.hasSuffix "\n" s || lib.hasSuffix "\r" s || lib.hasSuffix " " s || lib.hasSuffix "\t" s
    then
      trimRight (lib.substring 0 (lib.stringLength s - 1) s)
    else
      s;
  serviceScript = body: ''
    #!/bin/sh
    exec /bin/sh -c ${lib.escapeShellArg (trimRight body)} "$0" "$@"
  '';
  cleanupCommands = name: ''
    if test -d ${prefix}/${name} ; then rm -rf ${prefix}/${name} ; fi
  '';
  cleanupScript = name: cmds: ''
    #!/bin/sh
    ${if cmds != null then cmds else ""}
    ${cleanupCommands name}
  '';
  service =
    {
      name,
      serviceType,
      run ? null,
      up ? null,
      down ? null,
      finish ? null,
      notification-fd ? null,
      producer-for ? null,
      consumer-for ? null,
      pipeline-name ? null,
      timeout-up ? 30000, # milliseconds
      timeout-down ? 0,
      dependencies ? [ ],
      contents ? [ ],
      buildInputs ? [ ],
      restart-on-upgrade ? false,
      controller ? null,
      properties ? { },
    }:
    stdenvNoCC.mkDerivation {
      # we use stdenvNoCC to avoid generating derivations with names
      # like foo.service-mips-linux-musl
      inherit
        name
        serviceType
        up
        down
        run
        finish
        notification-fd
        producer-for
        consumer-for
        pipeline-name
        timeout-up
        timeout-down
        restart-on-upgrade
        ;
      propertiesText =
        let
          a = mapAttrsRecursive (
            path: value: "writepath ${concatStringsSep "/" path} ${builtins.toString value}\n"
          ) properties;
        in
        collect builtins.isString a;

      buildInputs =
        buildInputs ++ dependencies ++ contents ++ lib.optional (controller != null) controller;
      inherit controller dependencies contents;
      builder = ./builder.sh;
    };

  longrun =
    {
      name,
      run,
      finish ? null,
      notification-fd ? null,
      buildInputs ? [ ],
      producer-for ? null,
      ...
    }@args:
    let
      logger = service {
        serviceType = "longrun";
        name = "${name}-log";
        run = serviceScript "${s6}/bin/s6-log -d 10 -- p${name} 1";
        notification-fd = 10;
        consumer-for = name;
        pipeline-name = "${name}-pipeline";
      };
    in
    service (
      args
      // {
        buildInputs = buildInputs ++ lib.optional (producer-for == null) logger;
        serviceType = "longrun";
        run = serviceScript run;
        finish = cleanupScript name finish;
        producer-for = if producer-for != null then producer-for else "${name}-log";
      }
    );

  oneshot =
    {
      name,
      up,
      down ? "",
      ...
    }@args:
    service (
      args
      // {
        serviceType = "oneshot";
        up = writeScript "${name}-up" (serviceScript up);
        down = writeScript "${name}-down" (serviceScript "${down}\n${cleanupCommands name}");
      }
    );
  bundle =
    {
      contents ? [ ],
      dependencies ? [ ],
      ...
    }@args:
    service (
      args
      // {
        serviceType = "bundle";
        inherit contents dependencies;
      }
    );
  target = bundle;
in
{
  inherit
    target
    bundle
    oneshot
    output
    ;
  longrun = lib.makeOverridable longrun;
}
