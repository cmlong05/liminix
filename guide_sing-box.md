### sing-box 透明分流与 LAN SOCKS5

配置分三层：构建期规则集、构建期模板、运行时配置。

**规则集**：`sing-box/SOURCES.nix` 声明两份 binary rule-set，构建时用 `fetchurl` 下载并放进镜像：

```text
/etc/sing-box/rules/geoip-cn.srs
/etc/sing-box/rules/geosite-geolocation-!cn.srs
```

模板 `route.rule_set` 通过 `path` 引用它们，运行时不再下载，也不需要手工提供 JSON 规则文件。

**模板与运行时配置**：`/etc/sing-box/config.json.template` 是完整 JSON，构建时按 `jdcloudAx6600.singBox.tunName` 渲染 TUN 接口名。运行时配置在 `/var/lib/liminix/sing-box/config.json`，首次启动由服务从模板自动复制并设为 0600；已有文件不会被镜像覆盖。也可手工生成：

```sh
mkdir -m 0700 -p /var/lib/liminix/sing-box
cp /etc/sing-box/config.json.template /var/lib/liminix/sing-box/config.json
chmod 0600 /var/lib/liminix/sing-box/config.json
```

出站节点凭据不要写进仓库或模板，部署时填入运行时配置。修改后校验并重启：

```sh
vi /var/lib/liminix/sing-box/config.json
sing-box check -c /var/lib/liminix/sing-box/config.json
s6-rc -d change sing-box
s6-rc -u change sing-box
```

**服务行为**：sing-box 等 `wan` 与 `resolvconf` 就绪后才启动，等 TUN 接口出现才向 s6 报告 ready。配置缺失、`sing-box check` 失败或 TUN 一直没起来时服务保持 down 并每 60 秒重试，不会以「假 up」状态静默放行。防火墙全量重载会清掉 `auto_redirect` 建的 nft 表，已由 `firewall.restartAfterReload` 重启本服务重建。

**分流**：DNS 按规则分流；路由按 `geoip-cn` 直连、`geosite-geolocation-!cn` 走 `proxy`，`final` 为 `proxy`（未命中即走代理，不是直连）。

**LAN SOCKS5**：

```text
<router-lan-ip>:1080  TCP/UDP 固定走 proxy，不受 rule-set 影响
<router-lan-ip>:1081  TCP/UDP 固定走 direct，不受 rule-set 影响
```

## 两个入口只从 `@lan` 入方向放行，WAN 地址不能访问。`1080` 的域名解析和 DNS 流量随该入口走 `proxy`；`1081` 与透明流量不经过代理 DNS。dnsmasq 继续直接使用 WAN DNS。

**状态与故障旁路**：

```sh
s6-rc -a list | grep sing-box
ip rule show
ip route show table 2022
ip -6 route show table 2022
tail -n 100 /run/log/current
```

`auto_route` 默认使用表 2022。停止服务会移除它创建的路由与策略规则，LAN 恢复直连；dnsmasq 不受 sing-box 状态影响。

```sh
s6-rc -d change sing-box
ip rule show
ip route show table 2022
```
