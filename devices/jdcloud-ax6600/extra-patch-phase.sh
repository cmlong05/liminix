# The primitives the kernel derivation's extraPatchPhase is built from:
# default.nix sequences the calls, kernel-checks.nix generates the check
# calls from the `verify` records in the SOURCES.nix files.
#
# Sourced, not executed: the working directory (the unpacked kernel tree),
# the shell, and errexit/pipefail all come from stdenv's setup.

apply_patch() {
  patch -p1 --fuzz="$1" < "$2" || { echo "failed to apply $2"; exit 1; }
}

# What a patch must have left in the tree. `need` greps a whole file,
# `need_once` requires exactly one occurrence of the needle, `need_file`
# only that the file exists.
need() {
  grep -q "$2" "$1" || { echo "check failed: $3 ($1)"; exit 1; }
}

need_once() {
  test "$(grep -c "$2" "$1" || true)" = 1 || { echo "check failed: $3 ($1)"; exit 1; }
}

need_file() {
  test -f "$1" || { echo "check failed: $2 ($1)"; exit 1; }
}

# `needle` within `window` lines from the line holding `anchor`. Some
# needles sit in short braced blocks, and some occur elsewhere in the same
# file too, so for those a whole-file grep would prove nothing.
in_entry() {
  awk -v anchor="$2" -v needle="$3" -v win="$5" '
    BEGIN { if (win == "") win = 25 }
    index($0, anchor) { hit = 1 }
    hit { if (index($0, needle)) found = 1
          if (found || ++n > win) exit }
    END { exit found ? 0 : 1 }
  ' "$1" || { echo "check failed: $4 ($1)"; exit 1; }
}

# Mainline's qcom,ipq6018-wcss-pil node has to still be in the tarball: 0905
# rewrites its body and 0906 uses it as trailing context.
require_wcss_pil_in_tarball() {
  grep -q "qcom,ipq6018-wcss-pil" arch/arm64/boot/dts/qcom/ipq6018.dtsi ||
    { echo "ipq6018 wcss compatible missing from ipq6018.dtsi"; exit 1; }
}

# --no-preserve=mode: the store's read-only directory modes would leave the
# source root unwritable for the .config write the configure phase does.
install_overlay() {
  cp -a --no-preserve=mode "$1"/. .
}
