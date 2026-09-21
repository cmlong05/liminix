# The same kernel, built with no initramfs embedded.
#
# This exists to break a real dependency cycle. A fullSystem image embeds
# its whole rootdir, that rootdir carries loadable modules, those modules
# are built against `kernel.modulesupport` - and `modulesupport` is an
# output of the kernel derivation whose `INITRAMFS_SOURCE` points at that
# same image. Nothing can be built first.
#
# Dropping the image from the config is not possible: `kernel.config` is
# `attrsOf nonEmptyStr` and the option type checks every value, so the
# image path is forced before anything could remove it. That is why the
# image does not live in `kernel.config` at all - it is
# `kernel.initramfsSource`, a plain string option that the kernel builder
# appends after olddefconfig. Dropping it here is then just passing null.
#
# The result is the same source, patch phase, config and make targets as
# the real kernel, with one string differing. No exported symbol depends
# on INITRAMFS_SOURCE, so a module built against this kernel loads into
# the real one. The cost is a second kernel build, which is why this stays
# null unless something actually embeds an initramfs.
#
# Separate from ./default.nix because that module *owns* the kernel
# options: a definition of `kernel.*` in there cannot read
# `config.kernel.config` without being self-referential. Here `config` is
# a module argument like any other.
{ lib, pkgs, config, ... }:
let
  inherit (pkgs) liminix;

  mergeConditionals =
    conf: conditions:
    lib.foldlAttrs (
      acc: name: value:
      if (conf ? ${name}) && (conf.${name} != "n") then acc // value else acc
    ) conf conditions;
in
{
  config.kernel.modulesKernel =
    if !config.kernel.embedsInitramfs then
      null
    else
      liminix.builders.kernel.override {
        config = mergeConditionals config.kernel.config config.kernel.conditionalConfig;
        inherit (config.kernel) version src extraPatchPhase;
        rawConfigFile = config.kernel.rawConfig;
        targets = config.kernel.makeTargets;
        # the one difference from the real kernel
        initramfsSource = null;
      };
}
