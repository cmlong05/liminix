# The kernel side of N5 phase 1 (the IPQ6010 AHB radio), and the Q6
# firmware it runs.
#
# Nothing is committed: every patch and every firmware file is fetched at
# build time from the pins below, by URL and sha256. `sha256` is the flat
# hash of the file - reproduce it with
# `nix-hash --flat --type sha256 --sri <file>`.
#
# There is no local patch and no second kernel pin. That is the point of
# taking the fork's route rather than OpenWrt's:
#
#   OpenWrt adds IPQ6018 support *inside mainline's qcom_q6v5_wcss.c*.
#   Mainline has no ipq6018 driver data at all (6.18.y, 6.19.y and master
#   all checked), so that means eight patches supplying the compatible,
#   the firmware names, secure PIL, PRNG/QDSS_AT clocks, optional BCR
#   reset and auto-boot - and that set contradicts itself: 0905 forbids
#   "q6wcss" as the IPQ6018 SSR name while 0136, which adds the entry,
#   sets exactly that. Correcting it needs a ninth, local patch.
#
#   The fork adds a *separate* driver instead - drivers/remoteproc/
#   qcom_q6v5_wcss_sec.c - and points the device tree at its own
#   compatible. IPQ6018 is then one descriptor in it (0812: PAS id 6,
#   ss_name "wcnss", firmware names read from the device tree), mainline
#   is untouched, and every patch is upstream OpenWrt's, so all of them
#   are fetched. This is what the reference implementation runs.
#
# Consequence for the kernel config: QCOM_Q6V5_WCSS_SEC is the driver,
# not QCOM_Q6V5_WCSS, and "qcom_q6v5_wcss_sec" is what preloadModules
# loads (see ../default.nix and ./default.nix).
let
  ref = "683480add1822fdfbbdee77856753d7282d58b71";

  at =
    sub: ps:
    map (p: p // { url = "https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/${ref}/${sub}/${p.path}"; }) ps;

  # The Q6's own firmware, from the fork's firmware repository - the same
  # pin the reference implementation on this board runs.
  #
  # linux-firmware carries an IPQ6018/hw1.0 too, and that is the wrong
  # build for this host: its q6 image (fw_version WLAN.HK.2.7.0.1-02409,
  # "6018.wlanfw.evalQ") takes a fatal firmware exception the moment the
  # 5.8 GHz AP's BSS peer is created - i.e. on the first interface up of
  # phy0, before any channel or beacon is configured - and the radio never
  # comes up. BADVA in the crash dump is the interface's own MAC, so the
  # firmware dereferenced the peer address. Measured on the board
  # 2026-09-23: 2.7.0.1 crashes phy0's AP, this build does not, and 2.4 GHz
  # works on either. The m3 and the board data come from the same pin
  # because they are the same release as the q6 image; the per-unit
  # calibration stays ours (0:ART). See ../BRINGUP.md N5.
  fwRef = "0c817c46568ef6871042c7e2efc95ac24a1f02e6";
  fw =
    ps:
    map (p: p // { url = "https://raw.githubusercontent.com/VIKINGYFY/ath11k-firmware-ddwrt/${fwRef}/IPQ6018/hw1.0/${p.path}"; }) ps;

  # WLAN.HK.2.12-01460-QCAHKSWPL_SILICONZ-1: the split Q6 image (mdt + its
  # segments) and the m3 that 0808 loads into the carveout.
  q6Firmware = fw [
    { path = "q6_fw.mdt"; sha256 = "sha256-IiFLqgizMW5xCyts99GgvlcOmlOY6xdyCpzdYAvMfb0="; }
    { path = "q6_fw.b00"; sha256 = "sha256-G59H25r7WDx+SDgvZ5RawPhu3yVvizMdMBYufeUfYOQ="; }
    { path = "q6_fw.b01"; sha256 = "sha256-oxZC+LdbtajuCE5poJIUAzMkeITWM7OWo5nD6azmyX4="; }
    { path = "q6_fw.b02"; sha256 = "sha256-Vqzzv6TpzpdAt6NLfXagTIVsq1NEbvy8KECuU4pfrUs="; }
    { path = "q6_fw.b03"; sha256 = "sha256-3OhuAYzM1UcKkffV8SfEhO/6tSFzHDvq2p21HSbceB0="; }
    { path = "q6_fw.b04"; sha256 = "sha256-8rs6RYawb3qNQduoW+Fo5TP8pZST60ywvfUZOtpvpgI="; }
    { path = "q6_fw.b05"; sha256 = "sha256-g1irrxCay+6wgHWmJVcQjxuUjVAKsrxSL2c8EyvnYds="; }
    { path = "q6_fw.b07"; sha256 = "sha256-eBiVC0vch598hGu27Txi0w5MEnCG4TRSrNmcvRoXGZo="; }
    { path = "q6_fw.b08"; sha256 = "sha256-qIWQpMYmsluZaT3CymxHinIfpg414TUCpLbqJkLGDuE="; }
    { path = "m3_fw.mdt"; sha256 = "sha256-wRmqCkqPJNtiq+LEn5c+8adt0CYa0xAqc0zW5r4YEws="; }
    { path = "m3_fw.b00"; sha256 = "sha256-K/awGmLNLIhYYjnn+CC8jNquNIBawC4iftwBZYgJA5A="; }
    { path = "m3_fw.b01"; sha256 = "sha256-BfADzGtwy2rBmTE3rq6BUE9dAhTyQv6T6gbkk+OBPWc="; }
    { path = "m3_fw.b02"; sha256 = "sha256-RFvMuZQRUe+8cMng4d8bYbXtpE3byYgt4H9PpJdjMIY="; }
  ];

  # ath11k's board data, the fw.dir file of the ipq6018 hw params.
  boardData = fw [
    { path = "board-2.bin"; sha256 = "sha256-eIPKmmr4Uza2BV8PQsi6NeYfMagYMK6zzTCvugg5q3c="; }
  ];

  # The WCSS remoteproc and its device tree, in the fork's own order.
  # 0184 is here for one header, not for its driver; 0186 is bindings
  # documentation only; the rest is the driver, what it needs, and the
  # three dtsi patches that point ipq6018 at it. 0185 (qcom_scm: pass the
  # metadata size to the IPQ5332 TZ) is deliberately absent - it only
  # changes the PAS init call where the TZ advertises
  # QCOM_SCM_PIL_PAS_INIT_IMAGE_V2, which ipq6018 does not, so the
  # mainline two-argument call is what this board uses either way.
  wcss = at "target/linux/qualcommax/patches-6.18" [
    {
      path = "0184-mailbox-tmelite-qmp-Introduce-TMEL-QMP-mailbox-driver.patch";
      sha256 = "sha256-0JDhIOLK3sdJPq6UfdMfeKlH3sfzYAd1xwpua8/Sgnc=";
      note = ''
        Creates include/linux/mailbox/tmelcom-qmp.h, which 0188 includes
        unconditionally - the TME-L based authentication it carries is
        selected at runtime by desc->use_tmelcom, true only for the
        ipq5424 descriptor. The mailbox driver this patch also adds is
        not built: QCOM_TMEL_QMP_MAILBOX is left at its default n, and
        the WCSS driver calls nothing that lives in it.
      '';
    }
    {
      path = "0186-dt-bindings-remoteproc-qcom-document-hexagon-based-wcss-secure-pil.patch";
      sha256 = "sha256-JOrGY72yX/+U7t2kuiWUqkX36vrYXQ4iTK8XGfGCurs=";
      note = "documents the compatible; no build effect";
    }
    {
      path = "0188-remoteproc-qcom-add-hexagon-based-wcss-secure-pil-driver.patch";
      sha256 = "sha256-QZPECQPNUQun46+c2gljA4orgRkDs1GHG8ECkQ57sao=";
      note = ''
        The driver itself, a new file: loads the Q6 image through secure
        PIL (qcom_scm_pas_auth_and_reset), reads its firmware names from
        the device tree's firmware-name, and takes the optional "prng"
        and "qdss" clocks. Adds QCOM_Q6V5_WCSS_SEC.
      '';
    }
    {
      path = "0808-remoteproc-qcom-wcss-sec-add-split-firmware-support.patch";
      sha256 = "sha256-aNRPUacp4IjzWrvmfylB0jkHeHN1FWIRZzidT/XNsME=";
      note = "loads firmware-name[1] (the m3) into the carveout before the Q6 image";
    }
    {
      path = "0809-remoteproc-qcom-wcss-sec-enable-PRNG-clock.patch";
      sha256 = "sha256-bQdDetY2Cn088a9gfkpIsrj6L15Tkv1iraX8qq5hrm4=";
      note = "the Q6 clocks the PRNG block itself, so the host holds the proxy clock while it runs";
    }
    {
      path = "0810-remoteproc-qcom-wcss-sec-add-ipq8074-compatible.patch";
      sha256 = "sha256-ic4Vl6cIxG//QtH733y9RBi7O2hbXPT76d8MYO8iZrE=";
      note = "shared descriptor with ipq9574; 0812's of_match hunk sits next to it";
    }
    {
      path = "0811-remoteproc-qcom-wcss-sec-enable-qdss-clock.patch";
      sha256 = "sha256-plMWstOjB+0a1U+J2BvjjZp9TMJccnzELZ+iQ3j6oT0=";
      note = "the QDSS_AT clock the firmware needs while it runs";
    }
    {
      path = "0812-remoteproc-qcom-wcss-sec-add-ipq6018-support.patch";
      sha256 = "sha256-ikcOwvv0ox73aJTDvjMfjr0wmweKaM4TUavqMe5cdlY=";
      note = ''
        The one that matters here: an ipq6018 descriptor (pasid = 6) and
        its compatible. Its ss_name is "wcnss" - the name the SoC's RPM
        knows, and the reason the OpenWrt route needs a local patch and
        this one does not.
      '';
    }
    {
      path = "0905-arm64-dts-qcom-ipq6018-use-secure-WCSS-remoteproc.patch";
      sha256 = "sha256-02/wt9KvdLs1RKMCFOMNDUGS/gJD9cg6LolvY+tyHN4=";
      note = ''
        Points the ipq6018 q6v5_wcss node at that driver: the
        qcom,ipq6018-wcss-sec-pil compatible, firmware-name (which is how
        the driver learns IPQ6018/q6_fw.mdt + m3_fw.mdt), and the
        prng + qdss clocks. The node stays disabled in the dtsi; our
        overrides.dtsi enables it.
      '';
    }
    {
      path = "0906-arm64-dts-qcom-ipq6018-add-wifi-node.patch";
      sha256 = "sha256-J8PmbmQQjAQgBXOEL1l1dLqDb1g///j2iuNR30Jy70M=";
      note = ''
        The AHB radio's own node: qcom,ipq6018-wifi at 0xc000000, its 52
        interrupts and qcom,rproc = <&q6v5_wcss>, status disabled. 6.18.52
        does not have it - the board dts' &wifi override needs the label
        and ath11k matches on that compatible - so this is not optional.
        Order matters: its trailing context is the sec-pil compatible that
        0905 writes, and after 0905 it applies at fuzz 0.
      '';
    }
    {
      path = "0907-soc-qcom-fix-smp2p-ack-on-ipq6018.patch";
      sha256 = "sha256-tsM8B0QnHygKf+Tzh9QKYaj3L1ScFmpCNOxxuPRIDtg=";
      note = ''
        The Q6 sets the smp2p restart flag without negotiating the
        SMP2P_FEATURE_SSR_ACK feature, so mainline's ssr_ack path never
        fires and any Q6 reload (a stop, a crash, an ath11k reload) hangs
        waiting for an ack. First load works; the second one does not.
      '';
    }
  ];

  # ath11k. The fork's set is the only place these IPQ6018 AHB fixes
  # exist for this kernel generation. What is taken here is the subset
  # that carries this board's bring-up, in the fork's own order; the rest
  # is for other silicon (907 ipq5018, 920-925 QCN6122) or for the stages
  # past association (947, 949, 983, 984 - and 201, 453, 900, 905, which
  # are PCI, thermal and regulatory). Three entries of the bring-up set
  # are deliberately absent:
  #
  #   * 102 (mac_phy_caps_parse stride) is already in 6.18.52 - wmi.c has
  #     the kzalloc_objs() form - so there is nothing left to patch;
  #   * 100 (unique QRTR instance ID) is built on MHI_CB_EE_SBL_MODE,
  #     which 6.18.52's include/linux/mhi.h does not have, and it only
  #     matters once ath11k-pci drives the QCN9074 (phase 2);
  #   * 931 (m3 dump memory) writes into a local variable that comes from
  #     201, which this board has no use for, so it does not compile here
  #     - and it assigns nothing unless the wifi node carries
  #     qcom,m3-dump-addr, which no board dts in this tree sets.
  ath11k = at "package/kernel/mac80211/patches/ath11k" [
    {
      path = "101-wifi-ath11k-fix-wrong-usage-of-resource_size-causing.patch";
      sha256 = "sha256-5YZmbXFr26h42BVJqDGKFhFuo74ZWsBztlKv2gDLG9g=";
      note = ''
        resource_size() of the zeroed struct resource is 1, not 0, so
        assign_target_mem_chunk's CALDB case always took the "reserved
        region exists" branch and pointed the firmware's calibration at
        res.start + host_ddr_sz - garbage whenever HOST_DDR had not been
        seen first. Upstream's own subject for the fix is "causing
        firmware panic". 6.18.52 still has the buggy form, but the branch
        is latent here: 906 turns both coldboot_cal_* off for ipq6018, so
        ath11k_core_coldboot_cal_support() is false and it is not reached.
      '';
    }
    {
      path = "903-ath11k-support-setting-FW-memory-mode-via-DT.patch";
      sha256 = "sha256-u/e7IBdz9U8IDw4fAhBkTGDp23UP4coKWnh4mYQy2Fc=";
      note = ''
        Reads qcom,ath11k-fw-memory-mode into hw_params.fw_mem_mode, which
        qmi.c passes to the firmware as req.mem_cfg_mode, and which also
        picks num_vdevs/num_peers and the coldboot flags. The board dts
        taken from the fork sets <1> on the AHB node, so without this the
        property is inert and the radio runs at the per-hw default.
      '';
    }
    {
      path = "906-wifi-ath11k-disable-coldboot-for-ipq6018.patch";
      sha256 = "sha256-u5VC7cp1nM0Va0CsPauyjeBhRhytS02lN8pus9ZhuVw=";
      note = ''
        Coldboot calibration does not work on ipq6018 and fails wifi
        startup. Without it ath11k never asks for the calibration we
        extracted from ART and the radio comes up uncalibrated.
      '';
    }
    {
      path = "910-ath11k-fix-remapped-ce-accessing-issue-on-64bit-OS.patch";
      sha256 = "sha256-aiKQ1O3YhSxD27DrxcbJW9qpLdXKTc0izL5M2dPQeBk=";
      note = ''
        On 64-bit the CE register block is out of reach of the 32-bit
        offset arithmetic ath11k_ahb_read32/write32 do and the access
        data-aborts.
      '';
    }
    {
      path = "948-wifi-ath11k-Fix-the-WMM-param-type.patch";
      sha256 = "sha256-HeNwgsNRqP4uW/RpGlkfKxBpO035TB6ehTwBP5VqlqU=";
      note = "the firmware does not support the 11ax EDCA parameter and asserts when an AP start sends one";
    }
    {
      path = "950-wifi-ath11k-implement-CE-interrupt-enable-disable-for-AHB.patch";
      sha256 = "sha256-WJq+FosIE9CETVdqF9Y9cq9GgJIxB2Ui8d2C/MK8K8g=";
      note = ''
        ath11k_core_reset() disables CE interrupts before powering the
        target down, but the AHB hif ops had no ce_irq_enable/disable, so
        on AHB they stayed live across rproc_shutdown() and touched
        register space that was already gone.
      '';
    }
    {
      path = "950-wifi-ath11k-mask-undefined-board-id.patch";
      sha256 = "sha256-MloQEmGrXG7UfV/0EkTZdi4iFp6QV/D3h1SpIadg0BI=";
      note = ''
        board_id &= 0xFF: some firmwares report the undefined board id as
        0xffffffff instead of 0xff, which makes the board file lookup ask
        for qmi-board-id=-1 and fail.
      '';
    }
    {
      path = "951-wifi-ath11k-disable-interrupts-during-firmware-crash-recovery.patch";
      sha256 = "sha256-zTl1gUbRrrOR6MshMYFXizjiY+UQvX8FPshMaBwHz8A=";
      note = ''
        The AHB crash path (QMI server exit -> restart_work) never goes
        through ath11k_core_reset(), so its interrupts still run while the
        data path is torn down.
      '';
    }
  ];
in
{
  inherit ref fwRef q6Firmware boardData wcss ath11k;

  # What the build applies, in this order. `fuzz` is per group: 0 fails
  # the build on context drift rather than absorbing a hunk a few lines
  # from where it belongs. `ath11k` is the exception - 951's trailing
  # context names ath11k_cfr_deinit(), which mainline gained after
  # 6.18.52, and only that context differs.
  patches =
    let
      group = fuzz: ps: map (p: p // { inherit fuzz; }) ps;
    in
    group 0 wcss ++ group 3 ath11k;
}
