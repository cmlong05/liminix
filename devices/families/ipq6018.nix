# SoC family module for Qualcomm IPQ6018
#
# Kernel configuration common to all IPQ6018/IPQ6010 devices: clocks,
# pinctrl, the MSM serial console, the SDHCI (eMMC) controller and the
# KPSS watchdog (which U-Boot leaves running, so the kernel must take
# it over or the board will reset during boot).
#
# Board-specific details (device tree, load addresses, peripherals
# such as ethernet) belong in the device directory.
{

  lim,
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [
    ../../modules/arch/aarch64.nix
  ];

  config = {
    kernel.config = {
      # --- Qualcomm IPQ6018 SoC ---
      ARCH_QCOM = "y";
      # CRITICAL: the Cortex-A53 in IPQ6018 does not support 52-bit
      # virtual addressing. Without an explicit choice, olddefconfig
      # picks ARM64_VA_BITS_52 which builds a 5-level page table, and
      # the kernel crashes the instant the MMU is enabled in head.S
      # (no output, no panic - looks like a silent hang). OpenWrt
      # uses 39-bit VA (3 levels), which the A53 handles fine.
      ARM64_VA_BITS_39 = "y";
      ARM64_VA_BITS_52 = "n";
      # CRITICAL, same class of bug: 52-bit *physical* addressing
      # needs ARMv8.2-LPA which the A53 lacks. ARM64_PA_BITS_52
      # depends on ARM64_VA_BITS_52 (or 64K pages), so with VA_BITS_39
      # above olddefconfig would otherwise still pick 52-bit PA; the
      # 52-bit descriptor format is not understood by the A53 MMU ->
      # silent hang in head.S. OpenWrt uses 48-bit PA.
      ARM64_PA_BITS_48 = "y";
      # COMMON_CLK_QCOM gates the whole qcom clk menu (menuconfig),
      # IPQ_GCC_6018 lives inside it.
      COMMON_CLK_QCOM = "y";
      IPQ_GCC_6018 = "y";
      # pinctrl: PINCTRL_MSM is the core driver, PINCTRL_IPQ6018 the
      # SoC-specific one (in Kconfig.msm, inside `if PINCTRL_MSM`).
      GPIOLIB = "y";
      PINCTRL_MSM = "y";
      PINCTRL_IPQ6018 = "y";

      # --- serial console (qcom,msm-uartdm, ttyMSM0) ---
      SERIAL_MSM = "y";
      SERIAL_MSM_CONSOLE = "y";

      # --- eMMC (sdhc, qcom,sdhci-msm-v5); MMC_SDHCI_MSM depends on
      # MMC_SDHCI_PLTFM ---
      MMC = "y";
      MMC_SDHCI = "y";
      MMC_SDHCI_PLTFM = "y";
      MMC_SDHCI_MSM = "y";
      MMC_BLOCK = "y";

      # --- watchdog (qcom,kpss-wdt): U-Boot enables it, we must feed it ---
      WATCHDOG = "y";
      QCOM_WDT = "y";

      # --- status LEDs (no-serial-console bring-up diagnostics) ---
      NEW_LEDS = "y";
      LEDS_CLASS = "y";
      LEDS_GPIO = "y";

      # CRITICAL: msm_serial (and sdhci_msm) call
      # devm_pm_opp_set_clkname() in probe; PM_OPP is a hidden option
      # that is only enabled via `select` from cpufreq drivers.
      # Without it the OPP stub returns -EOPNOTSUPP (-95) and the
      # console never registers (the board boots, serial stays
      # silent). CPUFREQ_DT selects PM_OPP.
      PM = "y";
      CPU_FREQ = "y";
      CPU_FREQ_GOV_PERFORMANCE = "y";
      CPUFREQ_DT = "y";
      CPUFREQ_DT_PLATDEV = "y";

      # --- basics ---
      BLOCK = "y";
      DEVTMPFS = "y";
      DEVTMPFS_MOUNT = "y";
    };
  };
}
