# LAN 侧接口的唯一来源：桥的成员，同时用作防火墙 @lan zone。
#
# nft 的 iifname 匹配报文到达的物理口，oifname 匹配桥设备本身，所以
# @lan 里这两类名字都要有，否则 LAN 入向流量（DHCP/DNS/新连接）会被拒。
nifs: with nifs; [
  lan1
  lan2
  lan3
  lan4
  wlan24g
  wlan58g
]
