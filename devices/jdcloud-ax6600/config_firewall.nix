# 站点防火墙策略
#
# 这份规则不跟着镜像走：只有构建时显式指定才生效
#
#   -I liminix-firewall=./devices/jdcloud-ax6600/config_firewall.nix
#
# 不带该参数时镜像不带任何站点放行规则（build.sh 已带上）。每条是 nft
# 规则文本：incomingAllowedIp6 追加进默认留空的 incoming-allowed-ip6
# （转发与到本机两条链都会跳进去），appendRules 追加到规则集里已有的链
# 末尾，appendRulesBeforeLog 则插到链的 log 规则之前，链名见
# modules/firewall/default-rules.nix。
{
  # 公网 IPv6 访问 LAN 主机的入站连接。不限定 daddr：LAN 前缀来自
  # DHCPv6-PD、主机地址来自 SLAAC，写死会失效。
  incomingAllowedIp6 = [
    "oifname @lan tcp dport 5858 accept" # allow_SSH
    "oifname @lan tcp dport 8443 accept" # allow_ERP
    "oifname @lan tcp dport 8444 accept" # allow_wuju
    "oifname @lan tcp dport 9443 accept" # allow_nextcloud
  ];

  # allow port
  appendRules = {
      input-ip4-lan = [
        # 137/138 NetBIOS, 7083 海尔空调, 15000 美的洗衣机, 58866 石头扫地机
        "udp dport { 137, 138, 7083, 15000, 58866 } meta pkttype broadcast accept"
      ];
    };

  # input-ip6 以 log 规则收尾，而 log 没有 verdict、不会结束链：追加到末尾
  # 虽然仍然生效，每个匹配的包却会先被打一条 DENIED 日志，所以走这里。
  appendRulesBeforeLog = {
      # ip6 的 input 链不像 ip4 那样默认放行 lo，本机（dnsmasq 等）经
      # ::1 的解析请求会被拒；546 是 dhcp6c 收 DHCPv6-PD 回复的端口，
      # 在 ppp0 补进 @wan 集合之前也得能进。
      input-ip6 = [
        "iifname lo accept"
        "udp dport 546 accept"
      ];
    };
}
