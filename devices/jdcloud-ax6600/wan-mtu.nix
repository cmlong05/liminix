# What the WAN link can carry, as bytes of payload.
#
# PPPoE costs the ethernet frame 8 bytes of header (6 ethernet + 2 PPPoE
# protocol), an 802.1Q tag another 4: what is left is what pppd may
# advertise as MTU/MRU on the link we picked, and what the firewall may
# assume a LAN host can send.
{
  tagged = 1500 - 4 - 8;
  plain = 1500 - 8;
}
