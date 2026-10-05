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

# Enforce the file layout and language subset of CONVENTIONS.md (sections 2
# and 4) on the module, which is the repository root.
#
# Usage: hack/check-layout.sh [module-dir...] default: the repository root
#        hack/check-layout.sh --self-test     prove every rule fires on
#                                             hack/testdata/bad and none on
#                                             hack/testdata/good
#
# Prints `file:line: message` per violation and exits 1 when there is any.
#
# How it reads HCL: terraform fmt output is the only accepted formatting, so
# a top-level block starts at a line that begins in column 0 with an
# identifier and ends where the next one starts. Heredoc bodies and /* */
# comments are skipped; `#` and `//` comments are cut (quote-aware) before
# any pattern is matched. Known limits: a forbidden function name inside a
# string literal is reported too (a false positive, never a miss), and an
# unformatted file can confuse the block parser, so run fmt-check first.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")

# The per-file checks. -v f=<display path> -v base=<file name>.
read -r -d '' AWK_PROGRAM <<'EOF' || true
function viol(n, msg) { printf "%s:%d: %s\n", f, n, msg; bad++ }
function strip(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
# nocomment drops a trailing # or // comment that is outside a string.
function nocomment(s,   i, c, n, instr, out) {
  n = length(s); instr = 0; out = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (instr) {
      if (c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
      if (c == "\"") instr = 0
    } else {
      if (c == "\"") instr = 1
      else if (c == "#") break
      else if (c == "/" && substr(s, i + 1, 1) == "/") break
    }
    out = out c
  }
  return out
}
BEGIN {
  stem = base; sub(/\.tf$/, "", stem)
  fixed = 1
  if (base == "versions.tf") allowed = "terraform"
  else if (base == "providers.tf") allowed = "provider"
  else if (base == "variables.tf" || base == "variables_contract.tf") allowed = "variable"
  else if (base == "outputs.tf" || base == "outputs_extra.tf") allowed = "output"
  else if (base ~ /^locals_.+\.tf$/) allowed = "locals"
  else fixed = 0
  forbidden["module"] = "modules are flat: no `module` calls (CONVENTIONS.md section 2)"
  forbidden["check"] = "`check` blocks are not allowed: use a lifecycle precondition (CONVENTIONS.md section 2)"
  forbidden["moved"] = "`moved` blocks are not allowed (CONVENTIONS.md section 2)"
  forbidden["removed"] = "`removed` blocks are not allowed (CONVENTIONS.md section 2)"
  forbidden["import"] = "`import` blocks are not allowed (CONVENTIONS.md section 2)"
  forbidden["ephemeral"] = "`ephemeral` resources are not allowed (CONVENTIONS.md section 4)"
  heredoc = ""; incomment = 0; nres = 0; nterraform = 0
}
{
  raw = $0; sub(/\r$/, "", raw)
  if (heredoc != "") {
    if (strip(raw) == heredoc) heredoc = ""
    next
  }
  if (incomment) {
    if (index(raw, "*/")) incomment = 0
    next
  }
  if (raw ~ /^[ \t]*\/\*/) {
    if (!index(substr(raw, index(raw, "/*") + 2), "*/")) incomment = 1
    next
  }
  line = nocomment(raw)
  if (match(line, /<<-?[A-Za-z_][A-Za-z0-9_]*[ \t]*$/)) {
    heredoc = substr(line, RSTART, RLENGTH); sub(/^<<-?/, "", heredoc); heredoc = strip(heredoc)
  }

  if (line ~ /(^|[^A-Za-z0-9_.])(timestamp|uuid|plantimestamp|templatestring)[ \t]*\(/) {
    split("timestamp uuid plantimestamp templatestring", names, " ")
    for (k = 1; k in names; k++)
      if (line ~ ("(^|[^A-Za-z0-9_.])" names[k] "[ \t]*\\("))
        viol(NR, names[k] "() is not allowed: the modules must plan deterministically (CONVENTIONS.md section 4)")
  }
  if (line ~ /^[ \t]+backend[ \t]+"/)
    viol(NR, "`backend` blocks are not allowed: CAPTF generates the root module and owns the state (CONVENTIONS.md section 2)")
  if (line ~ /^[ \t]+cloud[ \t]*\{/)
    viol(NR, "`cloud` blocks are not allowed: CAPTF generates the root module and owns the state (CONVENTIONS.md section 2)")
  if (line ~ /^[ \t]*provisioner[ \t]+"/)
    viol(NR, "provisioners are not allowed (CONVENTIONS.md section 2)")

  if (line !~ /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*[{"]/) next

  type = line; sub(/[^A-Za-z0-9_-].*$/, "", type)
  split(line, q, "\"")
  label1 = q[2]; label2 = q[4]

  if (type in forbidden) { viol(NR, forbidden[type]); nforbidden++; next }

  if (fixed) {
    if (type != allowed)
      viol(NR, "`" type "` block in " base ": this file holds only `" allowed "` blocks (CONVENTIONS.md section 2)")
    if (type == "terraform" && ++nterraform > 1)
      viol(NR, "versions.tf holds exactly one `terraform` block")
    next
  }

  if (type != "resource" && type != "data") {
    viol(NR, "`" type "` block in " base ": a file outside the fixed set holds exactly one `resource` or `data` block (CONVENTIONS.md section 2)")
    next
  }
  if (label2 == "") { viol(NR, "`" type "` block without type and name labels"); next }
  if (++nres > 1) viol(NR, "second `" type "` block in " base ": one resource or data block per file (CONVENTIONS.md section 2)")
  want = (type == "data") ? "data_" label2 : label2
  if (nres == 1 && stem != want)
    viol(NR, "file stem '" stem "' must equal the block's local name: " (type == "data" ? "data source" : "resource") " \"" label2 "\" belongs in " want ".tf (CONVENTIONS.md section 2)")
  if (label2 ~ /^(this|main|default|example|self)$/)
    viol(NR, "local name \"" label2 "\" is not allowed: name the block <purpose>_<kind> (CONVENTIONS.md section 2)")
}
END {
  if (!fixed && nres == 0 && nforbidden == 0 && !bad)
    viol(1, base " holds no `resource` or `data` block: every file outside the fixed set holds exactly one (CONVENTIONS.md section 2)")
  if (base == "versions.tf" && nterraform == 0)
    viol(1, "versions.tf holds no `terraform` block")
  exit bad ? 1 : 0
}
EOF

# The directories under the repository root that are not module source:
# tooling (with its deliberately bad fixtures), build output and caches.
not_module=(-path "$root/hack" -o -path "$root/build" -o -path "$root/.cache" -o -path "$root/.tools" \
  -o -path "$root/.git" -o -path "$root/.github" -o -path "$root/examples" -o -name .terraform)

# check_module <dir>: print violations, return 1 when there is any.
check_module() {
  local dir=$1 rel out status=0 f base
  rel=${dir#"$root"/}
  [[ -d $dir ]] || { echo "check-layout: $rel is not a directory" >&2; return 1; }

  # Files that must not exist at all, anywhere under the module.
  while IFS= read -r f; do
    base=${f##*/}
    case $base in
      main.tf) echo "${f#"$root"/}:1: main.tf is not allowed: name each file after its block (CONVENTIONS.md section 2)" ;;
      *.tofu) echo "${f#"$root"/}:1: .tofu files are not allowed: the modules run on both runtimes (CONVENTIONS.md section 2)" ;;
      *.tf.json) echo "${f#"$root"/}:1: .tf.json files are not allowed (CONVENTIONS.md section 2)" ;;
    esac
    case $base in main.tf | *.tofu | *.tf.json) status=1 ;; esac
  done < <(find "$dir" \( "${not_module[@]}" \) -prune -o -type f -print | sort)

  # Modules are flat: a .tf file below the module directory is a nested module.
  while IFS= read -r f; do
    echo "${f#"$root"/}:1: .tf file below the module directory: modules are flat (CONVENTIONS.md section 2)"
    status=1
  done < <(find "$dir" \( "${not_module[@]}" \) -prune -o -type f -name '*.tf' -path "$dir/*/*" -print | sort)

  while IFS= read -r f; do
    base=${f##*/}
    [[ $base == main.tf ]] && continue
    out=$(awk -v "f=${f#"$root"/}" -v "base=$base" "$AWK_PROGRAM" "$f") || status=1
    [[ -z $out ]] || printf '%s\n' "$out"
  done < <(find "$dir" -maxdepth 1 -type f -name '*.tf' | sort)

  # Templates are rendered with templatefile(); the banned functions apply.
  while IFS= read -r f; do
    out=$(awk -v "f=${f#"$root"/}" '
      /[$%]\{([^}]*[^A-Za-z0-9_.])?(timestamp|uuid|plantimestamp|templatestring)[ \t]*\(/ {
        printf "%s:%d: template calls a function that is not allowed: timestamp, uuid, plantimestamp, templatestring (CONVENTIONS.md section 4)\n", f, NR; bad = 1
      }
      END { exit bad ? 1 : 0 }' "$f") || status=1
    [[ -z $out ]] || printf '%s\n' "$out"
  done < <(find "$dir/templates" -maxdepth 1 -type f -name '*.tftpl' 2>/dev/null | sort)

  return "$status"
}

self_test() {
  local good=$here/testdata/good bad=$here/testdata/bad out n=0 spec file want
  # file|message fragment: every rule must fire on its fixture.
  # shellcheck disable=SC2016 # backticks are message text, never commands
  local -a expect=(
    'main.tf|main.tf is not allowed'
    'extra.tofu|.tofu files are not allowed'
    'extra.tf.json|.tf.json files are not allowed'
    'nested/inner.tf|modules are flat'
    'two_blocks.tf|second `resource` block'
    'wrong_stem.tf|file stem '"'"'wrong_stem'"'"' must equal'
    'node_image.tf|belongs in data_node_image.tf'
    'this.tf|local name "this" is not allowed'
    'forbidden_blocks.tf|no `module` calls'
    'forbidden_blocks.tf|`check` blocks are not allowed'
    'forbidden_blocks.tf|`moved` blocks are not allowed'
    'forbidden_blocks.tf|`removed` blocks are not allowed'
    'forbidden_blocks.tf|`import` blocks are not allowed'
    'forbidden_blocks.tf|`ephemeral` resources are not allowed'
    'versions.tf|`backend` blocks are not allowed'
    'versions.tf|`provider` block in versions.tf'
    'versions.tf|exactly one `terraform` block'
    'providers.tf|`resource` block in providers.tf'
    'locals_names.tf|`variable` block in locals_names.tf'
    'variables.tf|`output` block in variables.tf'
    'outputs_extra.tf|`locals` block in outputs_extra.tf'
    'functions.tf|timestamp() is not allowed'
    'functions.tf|uuid() is not allowed'
    'functions.tf|plantimestamp() is not allowed'
    'functions.tf|templatestring() is not allowed'
    'functions.tf|provisioners are not allowed'
    'misc.tf|`variable` block in misc.tf'
    'empty.tf|holds no `resource` or `data` block'
    'templates/user_data.tftpl|template calls a function'
  )

  if ! out=$("$0" "$good" 2>&1); then
    echo "self-test: hack/testdata/good must pass, got:" >&2
    printf '%s\n' "$out" >&2
    return 1
  fi
  if out=$("$0" "$bad" 2>&1); then
    echo "self-test: hack/testdata/bad must fail" >&2
    return 1
  fi
  for spec in "${expect[@]}"; do
    file=${spec%%|*}
    want=${spec#*|}
    if ! grep -F -- "/$file:" <<<"$out" | grep -qF -- "$want"; then
      echo "self-test: no violation '$want' reported for $file; output was:" >&2
      printf '%s\n' "$out" >&2
      return 1
    fi
    n=$((n + 1))
  done
  echo "check-layout: self-test ok ($n expected violations reported, good fixture clean)"
}

if [[ ${1:-} == --self-test ]]; then
  self_test
  exit
fi

modules=()
if (($# > 0)); then
  for d in "$@"; do modules+=("$(cd "$d" && pwd)"); done
else
  modules=("$root")
fi

failed=0
for d in "${modules[@]}"; do
  check_module "$d" || failed=$((failed + 1))
done
if ((failed > 0)); then
  echo "check-layout: FAIL: $failed module(s) with violations" >&2
  exit 1
fi
echo "check-layout: ok (${#modules[@]} module(s))"
