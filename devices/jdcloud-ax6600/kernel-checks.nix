# Generates the kernel-tree checks as calls to the primitives in
# extra-patch-phase.sh, from the `verify` records the SOURCES.nix entries
# carry. A check on a patch lives on that patch's entry, so it is dropped,
# moved or rewritten with it.
{ lib }:
let
  q = lib.escapeShellArg;

  line =
    c:
    {
      grep = "need ${q c.file} ${q c.needle} ${q c.label}";
      entry = "in_entry ${q c.file} ${q c.anchor} ${q c.needle} ${q c.label} ${toString (c.window or 25)}";
      once = "need_once ${q c.file} ${q c.needle} ${q c.label}";
      file = "need_file ${q c.file} ${q c.label}";
    }
    .${c.kind};

  # The checks with no patch to hang on: what the two overlays the phase
  # installs have to have put in the tree.
  installed = [
    {
      kind = "file";
      file = "include/net/netfilter/nf_conntrack_dscpremark_ext.h";
      label = "dscpremark header not installed";
    }
    {
      kind = "grep";
      file = "arch/arm64/boot/dts/qcom/ipq6018-ess.dtsi";
      needle = "ess-switch@3a000000";
      label = "ESS dtsi not installed correctly";
    }
    {
      kind = "file";
      file = "include/dt-bindings/net/qcom-ipq-ess.h";
      label = "ESS constants header not installed";
    }
  ];
in
{
  inherit installed;
  lines = checks: lib.concatMapStringsSep "\n" line checks;
}
