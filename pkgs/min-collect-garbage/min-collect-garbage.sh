#!/bin/sh
set -eu
manifest=/persist/nix-store-paths
test -f "$manifest" || manifest=/nix-store-paths
test -f "$manifest" || exit 1
(cd /nix/store && min-list-garbage "$manifest" | xargs -r rm -r) || exit 1

for dir in / /persist; do
  test -d "$dir" || continue
  for link in "$dir"/*.configuration; do
    test -L "$link" || continue
    target=$(readlink "$link")
    case "$target" in
      /nix/store/*) test -e "$target" || rm "$link" ;;
    esac
  done
done
