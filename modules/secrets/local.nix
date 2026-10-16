# A secrets source that reads a plain JSON file from the running system
# 
{
  liminix,
  lib,
  json-to-fstree,
}:
{
  name,
  path,
  seed ? null,
  interval ? 1,
}:
let
  inherit (liminix.services) longrun;
  dir = builtins.dirOf path;

  choose-source = lib.optionalString (seed != null) ''
    if grep -qs " ${dir} " /proc/mounts ; then
        if ! test -e ${path} ; then
            cp ${seed} ${path}
            chmod 0600 ${path}
        fi
        source=${path}
    else
        source=${seed}
    fi
    if test "$source" != "${seed}" && ! ${json-to-fstree}/bin/json-to-fstree file://$source ${placeholder "out"} ; then
        echo "cannot read $source, using ${seed}" >&2
        source=${seed}
    fi
  '';
in
longrun {
  inherit name;
  buildInputs = [ json-to-fstree ];
  notification-fd = 10;
  run = ''
    source=${path}
    ( in_outputs ${name}
      ${choose-source}
      ready=
      while : ; do
        if ${json-to-fstree}/bin/json-to-fstree file://$source ${placeholder "out"} ; then
          # notify readiness exactly once: s6 closes the pipe behind the
          # notification fd after it has seen the notification, so writing
          # to it on a later pass raises SIGPIPE and kills the service
          if test -z "$ready" ; then echo ready >&10 ; ready=1 ; fi
        fi
        sleep ${builtins.toString (interval * 60)}
      done
    )
  '';
}
