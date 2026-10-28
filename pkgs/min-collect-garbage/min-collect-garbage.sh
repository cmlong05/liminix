#!/bin/sh
manifest=/persist/nix-store-paths
test -f "$manifest" || manifest=/nix-store-paths
test -f "$manifest" || exit 1
(cd /nix/store && min-list-garbage "$manifest" | xargs rm -r)

for dir in / /persist; do
  test -d "$dir" || continue
  for link in "$dir"/*.configuration; do
    test -L "$link" || continue
    test -e "$link" || rm "$link"
  done
done
