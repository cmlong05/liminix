{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    escapeShellArg
    mapAttrsToList
    mkIf
    optionalString
    ;

  o = config.system.outputs;

  # Everything the root filesystem needs: the store closure of
  # config.filesystem's references plus the system configuration.
  closure = pkgs.pkgsBuildBuild.closureInfo {
    rootPaths = [
      (pkgs.pseudofile.write "files.pf" config.filesystem.contents)
      o.systemConfiguration
    ];
  };

  # config.filesystem is a pseudofile tree, so expand it into the shell
  # commands that create the nodes the squashfs image would have carried
  # (pseudofile's "i" is a fifo, matching mksquashfs's "filename i mode
  # uid gid f"). Modes matter: the runimage's ./run scripts have to be
  # executable. Device nodes need root, and s6-linux-init mounts devtmpfs
  # on /dev itself (DEVTMPFS_MOUNT = "n" in the device config), so failing
  # to create those is survivable.
  populate =
    prefix: attrs:
    concatStringsSep "\n" (
      mapAttrsToList (
        name: node:
        let
          # pseudofile treats an absent type as a plain file
          type = node.type or "f";
          # ... and an absent mode as 0755 for directories, 0644 otherwise
          mode = node.mode or (if type == "d" then "0755" else "0644");
          path = escapeShellArg "${prefix}/${name}";
        in
        if type == "d" then
          "mkdir -p ${path}\nchmod ${mode} ${path} 2>/dev/null || echo \"populate: ${path} keeps the default mode\" >&2\n${populate "${prefix}/${name}" node.contents}"
        else if type == "s" then
          "ln -sfn ${escapeShellArg node.target} ${path}"
        else if type == "l" then
          "ln ${escapeShellArg node.target} ${path}"
        else if type == "i" then
          "test -p ${path} || { mkfifo ${path}; chmod ${mode} ${path}; }"
        else if type == "c" || type == "b" then
          # needs root: unprivileged the node is missing, which
          # s6-linux-init's devtmpfs then covers
          "test ${if type == "c" then "-c" else "-b"} ${path} || mknod -m ${mode} ${path} ${type} ${node.major} ${node.minor} || echo \"populate: ${path} not created (need root and CAP_MKNOD?)\" >&2"
        else
          "printf '%s' ${escapeShellArg (node.file or "")} > ${path}\nchmod ${mode} ${path}"
      ) attrs
    );

  # Lay the whole filesystem down at $PWD/tree, in the build directory.
  buildTree = ''
    tree=$PWD/tree
    mkdir -p "$tree/nix/store"
    while read -r path; do
      cp -a "$path" "$tree$path"
    done < ${closure}/store-paths
    (
      cd "$tree"
      ${populate "." config.filesystem.contents}
      # A tree without config.filesystem would only fail later, on the device
      test -L bin/init
    )
  '';
in
{
  imports = [
    ./initramfs.nix
  ];
  config = mkIf (config.rootfsType == "ext4") {
    kernel.config = {
      EXT4_FS = "y";
      EXT4_USE_FOR_EXT2 = "y";
      FS_ENCRYPTION = "y";
    };
    boot.initramfs.enable = mkIf (config.boot.rootfs.mount == "initramfs") true;
    system.outputs = {
      rootfs =
        let
          inherit (pkgs.pkgsBuildBuild) e2fsprogs runCommand;
          kernelMount = config.boot.rootfs.mount == "kernel";
        in
        runCommand "mkfs.ext4"
          {
            depsBuildBuild = [ e2fsprogs ];
          }
          ''
            ${optionalString kernelMount buildTree}
            ${optionalString (!kernelMount) "tree=${o.bootablerootdir}"}
            size=$(du -s --apparent-size --block-size 1024 "$tree" |cut -f1)
            # add 25% for filesystem overhead
            size=$(( 5 * $size / 4))
            dd if=/dev/zero of=$out bs=1024 count=$size
            mke2fs -t ext4 -j -d "$tree" $out
          '';
    };
  };
}
