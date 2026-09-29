# The deployment as it appears in /persist/config.json: one definition
# shared by the image seed (ax6600-lan.nix) and gen-config-json.sh.
{ lib }:
let
  deployment =
    let
      lookup = builtins.tryEval <liminix-deployment>;
    in
    if lookup.success && builtins.pathExists (toString lookup.value) then
      import lookup.value
    else
      import ./config.nix;

  # Leaves are stringified, not merely JSON-encoded: 24 becomes "24" and
  # true becomes "1". The reader side accepts strings and objects only, so
  # a JSON number or boolean reads back as an absent key.
  seedValue =
    v:
    if builtins.isAttrs v then
      lib.filterAttrs (_: x: x != null) (lib.mapAttrs (_: seedValue) v)
    else if builtins.isList v then
      map seedValue v
    else if v == null then
      null
    else
      toString v;

  # builtins.toJSON writes the whole tree on one line; this indents it so
  # the file dropped in /persist stays readable and hand-editable.
  prettyJson =
    let
      pad = n: lib.concatStringsSep "" (lib.genList (_: "  ") n);
      go =
        depth: v:
        if builtins.isAttrs v then
          if v == { } then
            "{}"
          else
            "{\n"
            + lib.concatStringsSep ",\n" (
              lib.mapAttrsToList (
                k: x: "${pad (depth + 1)}${builtins.toJSON k}: ${go (depth + 1) x}"
              ) v
            )
            + "\n${pad depth}}"
        else if builtins.isList v then
          if v == [ ] then
            "[]"
          else
            "[\n"
            + lib.concatStringsSep ",\n" (map (x: "${pad (depth + 1)}${go (depth + 1) x}") v)
            + "\n${pad depth}]"
        else
          builtins.toJSON v;
    in
    go 0;
in
{
  inherit deployment seedValue prettyJson;
  text = prettyJson (seedValue deployment) + "\n";
}
