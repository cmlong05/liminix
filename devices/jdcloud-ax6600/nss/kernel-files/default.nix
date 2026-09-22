# The kernel-tree files this device's kernel phase installs: neither a
# patch nor a module, but files that exist only in the fork's target
# files/ tree and have to be in the kernel source before it compiles (the
# fork copies that whole tree in, which is why no patch creates them).
#
# Both groups are recorded with their fork path and blob sha in the
# device's SOURCES.nix - that file is for provenance, this one only for
# the bytes:
#
#   * kernelNetfilterFiles - the conntrack DSCPREMARK extension 0600-6
#     refers to but does not create;
#   * skbRecyclerFiles - the six files 0981-1 compiles.
#
# Each entry's `path` is where it lands in the kernel tree, so the
# device's extraPatchPhase can `cp -a` the whole output in.
{
  pkgsBuildBuild,
  sources,
}:
let
  # Blob-pinned raw URLs from the same fork commit as SOURCES.nix; flat
  # hashes, so fetchurl is enough.
  file =
    f:
    pkgsBuildBuild.fetchurl {
      name = baseNameOf f.path;
      url = "${sources.upstream.rawBase}/${f.forkPath}";
      inherit (f) sha256;
    };

  install =
    f:
    "install -D -m 0644 ${file f} $out/${f.path}\n";

  groups = [
    sources.kernelNetfilterFiles
    sources.skbRecyclerFiles
  ];
in
pkgsBuildBuild.runCommand "ipq6010-nss-kernel-files" { } (
  "mkdir -p $out\n"
  + builtins.concatStringsSep "" (map install (builtins.concatLists groups))
)
