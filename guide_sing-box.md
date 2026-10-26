
### sing-box 透明分流与 LAN SOCKS5

# 手动提供两份 source rule-set JSON：
```text
/var/lib/liminix/sing-box/proxy.json
/var/lib/liminix/sing-box/bypass.json
```
# 文件格式：
```json
{
  "version": 1,
  "rules": [
    {
      "domain_suffix": [
        ".example.com"
      ]
    }
  ]
}
```
# 规则完全由运行时文件提供，不需要写入部署配置或在构建时下载。镜像提供配置模板，运行时配置需要手动复制并修改：
```sh
mkdir -m 0700 -p /var/lib/liminix/sing-box
cp /etc/sing-box/config.json.template /var/lib/liminix/sing-box/config.json
chmod 0600 /var/lib/liminix/sing-box/config.json
```
# 编辑运行时配置，将 `proxy` 出站骨架改成实际代理，保持 tag 为 `proxy`：

```sh
vi /var/lib/liminix/sing-box/config.json
sing-box check -c /var/lib/liminix/sing-box/config.json
s6-rc -d change sing-box
s6-rc -u change sing-box
```

# 已有 `config.json` 不会随镜像覆盖。两份规则文件缺失或配置校验失败时，服务不安装透明路由，LAN 保持直连。

# 透明流量中的 DNS 固定直连，之后按 `bypass` 规则直连、私网直连、`proxy`规则走代理，其余直连。LAN 可使用两个无认证 SOCKS5 入口：
```text
<router-lan-ip>:1080  TCP/UDP 固定走 proxy，不受 rule-set 影响
<router-lan-ip>:1081  TCP/UDP 固定走 direct，不受 rule-set 影响
```

## 两个入口只从 `@lan` 入方向放行，WAN 地址不能访问。
## `1080` 的域名解析和DNS 流量随该入口走 `proxy`；`1081` 与透明流量不经过代理 DNS。dnsmasq 继续直接使用 WAN DNS。

## 查看状态和日志：
```sh
s6-rc -a list | grep sing-box
ip rule show
ip route show table 2022
ip -6 route show table 2022
tail -n 100 /run/log/current
```

## `auto_route` 默认使用表 2022。故障旁路：停止服务会移除它创建的路由与策略规则，LAN 恢复直连。dnsmasq 不受 sing-box 状态影响。配置缺失或 `sing-box check` 失败时服务不安装透明路由。

```sh
s6-rc -d change sing-box
ip rule show
ip route show table 2022
```
