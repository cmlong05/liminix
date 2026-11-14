{
  writeAshScript,
  liminix,
  svc,
  lib,
  s6,
  s6-rc,
  s6-rc-up-tree,
  serviceFns,
  output-template,
}:
{
  command,
  name,
  debug,
  username,
  password,
  lcpEcho,
  bandwidth,
  ppp-options,
  timeout-up ? null,
  redial-interval ? 30,
  redial-dependents ? [ ],
  dependencies ? [ ],
}:
let
  inherit (lib)
    optional
    optionals
    optionalString
    escapeShellArgs
    ;
  inherit (liminix.services) longrun;
  inherit (builtins) toJSON toString;
  # 显式设置的 timeout-up 优先；否则沿用旧行为，随 lcpEcho 自动放大——
  # 回声间隔长的链路， negotiation 也需要更长的就绪窗口
  timeoutUp =
    if timeout-up != null then
      timeout-up
    else if lcpEcho.failure != null && lcpEcho.interval != null then
      (10 + lcpEcho.failure * lcpEcho.interval) * 1000
    else
      60 * 1000;

  ip-up = writeAshScript "ip-up" { } ''
    exec >&5 2>&5
    . ${serviceFns} 
    in_outputs ${name}
    echo $1 > ifname
    echo $2 > tty
    echo $3 > speed
    echo $4 > address
    echo $5 > peer-address
    cat /sys/class/net/$1/ifindex > ifindex
    set +o nounset
    if test -n "''${DNS1}" ;then echo ''${DNS1} > ns1 ; fi
    if test -n "''${DNS2}" ;then echo ''${DNS2} > ns2 ; fi
    touch ip-up
    # IPv4 通了就算起来：ISP 不给 IPv6（或 IPv6 迟到）时不应该让 WAN 起不来
    echo >/proc/self/fd/10 || true
  '';
  ip6-up = writeAshScript "ip6-up" { } ''
    exec >&5 2>&5
    . ${serviceFns} 
    in_outputs ${name}
    echo $5 > ipv6-peer-address
    echo $4 > ipv6-address
    touch ipv6-up
    test -e ip-up && ( echo >/proc/self/fd/10 || true)
  '';
  isOutputRef = o: builtins.isFunction o || (builtins.isAttrs o && o ? __functor);
  literal_or_output =
    let
      v =
        o:
        if isOutputRef o then
          "output(${toJSON (o "service")}, ${toJSON (o "path")})"
        else
          toJSON o;
    in
    o: "{{ ${v o} }}";

  ppp-options' = [
    "+ipv6"
    "noauth"
  ]
  ++ optional debug "debug"
  ++ optionals (username != null) [
    "name"
    (literal_or_output username)
  ]
  ++ optionals (password != null) [
    "password"
    (literal_or_output password)
  ]
  ++ optional lcpEcho.adaptive "lcp-echo-adaptive"
  ++ optionals (lcpEcho.interval != null) [
    "lcp-echo-interval"
    (toString lcpEcho.interval)
  ]
  ++ optionals (lcpEcho.failure != null) [
    "lcp-echo-failure"
    (toString lcpEcho.failure)
  ]
  ++ map (o: if isOutputRef o then literal_or_output o else o) ppp-options
  ++ optional (!(builtins.elem "defaultroute" ppp-options)) "nodefaultroute"
  ++ [
    "ip-up-script"
    ip-up
    "ipv6-up-script"
    ip6-up
    "ipparam"
    name
    "nodetach"
    # usepeerdns requests DNS servers from peer (which is good),
    # then attempts to write them to /nix/store/xxxx/ppp/resolv.conf
    # which causes an unsightly but inconsequential error message
    "usepeerdns"
    "logfd"
    "2"
  ];
  # 启动超时（或任何 up 转换失败）会让 s6-rc 把服务标 down，此后
  # s6-supervise 不再拉起 pppd，线路恢复也没人管。s6-rc 的 change 只 up
  # 服务本身和它的依赖，不 up 依赖它的服务，所以挂一个长驻服务，用
  # s6-rc-up-tree 拉起整棵反向依赖树（它会跳过被 down 掉的 controlled 服务）。
  redial = longrun {
    name = "${name}-redial";
    run = ''
      dir=/run/service/${name}
      until test -d $dir/supervise ; do sleep 1 ; done
      # up-tree 调裸名 s6-rc / s6-rc-db
      export PATH=${s6-rc}/bin:${s6}/bin:${s6-rc-up-tree}/bin:$PATH
      # 等 boot 的 up 序列交出 s6-rc 锁，否则会抢在 runlevel 前面启动服务
      s6-rc -b -a list >/dev/null 2>&1 || true
      while : ; do
        ${s6}/bin/s6-svwait -d $dir
        # 没有可拉起的服务时 up-tree 退出 1
        s6-rc-up-tree ${name} || true
        ${optionalString (redial-dependents != [ ]) ''
          # 图里查不到的服务（不声明对 WAN 的依赖）才需要在这里列出
          s6-rc -b -u change ${escapeShellArgs redial-dependents} || true
        ''}
        sleep ${toString redial-interval}
      done
    '';
  };
  service = longrun {
    inherit name;
    run = ''
      mkdir -p /run/${name}
      chmod 0700 /run/${name}
      in_outputs ${name}
      echo ${escapeShellArgs ppp-options'} | ${output-template}/bin/output-template '{{' '}}' > /run/${name}/ppp-options
      fdmove -c 5 2 \
      ${command}
    '';
    notification-fd = 10;
    properties.bandwidth = bandwidth;
    timeout-up = timeoutUp;
    dependencies = dependencies ++ [ redial ];
  };
in
svc.secrets.subscriber.build {
  watch = lib.filter isOutputRef (ppp-options ++ [
    username
    password
  ]);
  inherit service;
}
