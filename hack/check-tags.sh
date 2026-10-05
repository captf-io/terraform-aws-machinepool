#!/usr/bin/env bash
# Copyright 2026 The CAPTF Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Enforce CONVENTIONS.md section 7: every resource whose type has the
# cloud's tag attribute sets it from local.tags.
#
# Usage: hack/check-tags.sh   checks the module at the repository root
#
# hack/tags.json:
#   attribute   the cloud's top-level tag or label attribute
#   expression  what the attribute must be built from (a literal, e.g. local.tags)
#   exempt      { "<resource type>": "<reason>" } for types that cannot or
#               need not carry it
#
# The script reads the provider schema (`providers schema -json` on the
# staged module, in the pinned Terraform container; see
# hack/tf-run.sh), lists the resource types that have the attribute, and for
# every top-level `resource "<type>" "<name>"` of such a type that is not
# exempt requires an `  <attribute> = ...<expression>...` argument in the
# block (continuation lines included). Nested taggables (volume tags, launch
# template tag specifications, VNIC details) are checked in review: this
# script sees top-level arguments only. Data sources are not checked.
#
# Needs jq on the host and the container engine. Env: ENGINE (podman|docker,
# default podman), TF_IMAGE_terraform (the Makefile exports it).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
cd "$root"

command -v jq >/dev/null || { echo "check-tags: jq not found" >&2; exit 2; }
conf=hack/tags.json
attr=$(jq -er '.attribute' "$conf")
expr=$(jq -er '.expression' "$conf")
# The expression is a literal: escape the regex metacharacters it may hold.
expr_re=$(printf '%s' "$expr" | sed 's/[][\.^$*+?(){}|/]/\\&/g')


# resource_blocks <file>: print "line<TAB>type<TAB>name<TAB>has_tag" per top-level resource block.
resource_blocks() {
  # ENVIRON, not -v: -v would process the backslashes in the regex.
  ATTR=$attr EXPR_RE=$expr_re awk '
    function flush() {
      if (type != "") printf "%d\t%s\t%s\t%d\n", start, type, name, ok
      type = ""
    }
    function depth_delta(s,   t, o, c) {
      t = s; gsub(/"([^"\\]|\\.)*"/, "", t)
      o = gsub(/[({\[]/, "", t); c = gsub(/[)}\]]/, "", t)
      return o - c
    }
    BEGIN { attr = ENVIRON["ATTR"]; expr = ENVIRON["EXPR_RE"] }
    /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*[{"]/ {
      flush()
      split($0, q, "\"")
      if ($1 == "resource") { type = q[2]; name = q[4]; start = NR; ok = 0; open = 0 }
      next
    }
    type != "" {
      if (open) {
        if ($0 ~ expr) ok = 1
        open += depth_delta($0)
        next
      }
      if ($0 ~ ("^  " attr "[ \t]*=")) {
        if ($0 ~ expr) ok = 1
        open = depth_delta($0)
      }
    }
    END { flush() }
  ' "$1"
}

failures=0
ENGINE=${ENGINE:-podman} hack/tf-run.sh schema terraform default >/dev/null
schema=build/schema/terraform.json
tagged=$(jq -r --arg a "$attr" '
  [.provider_schemas[].resource_schemas | to_entries[]
   | select(.value.block.attributes[$a] != null) | .key] | unique[]' "$schema")
checked=0
for f in ./*.tf; do
  [[ -e $f ]] || continue
  f=${f#./}
  while IFS=$'\t' read -r line type name ok; do
    grep -qxF -- "$type" <<<"$tagged" || continue
    reason=$(jq -r --arg t "$type" '.exempt[$t] // empty' "$conf")
    if [[ -n $reason ]]; then
      echo "check-tags: $f:$line: $type.$name exempt: $reason"
      continue
    fi
    checked=$((checked + 1))
    if [[ $ok != 1 ]]; then
      echo "$f:$line: $type \"$name\" has a '$attr' attribute in the provider schema but does not set it from $expr (CONVENTIONS.md section 7); set '$attr = $expr' or add the type to hack/tags.json with a reason" >&2
      failures=$((failures + 1))
    fi
  done < <(resource_blocks "$f")
done

if ((failures > 0)); then
  echo "check-tags: FAIL: $failures resource(s) do not set $attr from $expr" >&2
  exit 1
fi
echo "check-tags: ok ($checked taggable resource(s))"
