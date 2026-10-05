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

# Runs shellcheck over the repository's shell: hack/*.sh and every shell
# template under templates/ (CONVENTIONS.md section 15).
#
# A template is shell when its first line is a shell shebang or
# `#cloud-boothook`, or when it carries a `# shellcheck shell=<dialect>`
# directive. A boothook's `#cloud-boothook` line and the shebang under it
# swap places, as cloud-init strips the header before it runs the script.
# It is rendered for shellcheck with placeholders: `$${` becomes
# `${`, `%%{` becomes `%{`, every other `${...}` interpolation becomes the
# word `captf_template_value`, and template directive lines (`%{ if }`,
# `%{ endfor }`, ...) become blank lines, so reported line numbers match the
# template. Rendered copies land in build/shellcheck/.
#
#   hack/check-shell.sh
#
# Env: ENGINE (podman|docker, default podman), SHELLCHECK_IMAGE (pinned
# image; the Makefile passes it).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

engine="${ENGINE:-podman}"
image="${SHELLCHECK_IMAGE:?SHELLCHECK_IMAGE must name the pinned shellcheck image}"
out=build/shellcheck

# Remove only what this script writes.
if [[ -d "$out" ]]; then
  rm -rf -- "${root:?}/$out"
fi
mkdir -p "$out"

# dialect <file>: sh or bash, from the shebang or a shellcheck directive.
dialect() {
  local first
  first="$(head -n 1 "$1")"
  if [[ "$first" == '#!'*bash* ]] || grep -qE '^# shellcheck shell=bash' "$1"; then
    echo bash
  else
    echo sh
  fi
}

is_shell_template() {
  local first
  first="$(head -n 1 "$1")"
  [[ "$first" == '#!'*sh* || "$first" == '#cloud-boothook'* ]] ||
    grep -qE '^# shellcheck shell=' "$1"
}

render() {
  perl -pe '
    if ($. == 1 && /^#cloud-boothook/) { $hook = $_; $_ = ""; next; }
    if ($. == 2 && defined $hook) {
      $_ = /^#!/ ? $_ . $hook : $hook . $_;
      undef $hook;
      next;
    }
    if (/^\s*%\{[^}]*\}\s*$/) { $_ = "\n"; next; }
    s/\$\$\{/\x01/g;
    s/%%\{/\x02/g;
    s/%\{[^}]*\}//g;
    s/\$\{[^}]*\}/captf_template_value/g;
    s/\x01/\${/g;
    s/\x02/%{/g;
  ' "$1"
}

declare -a sh_files=() bash_files=()

add() {
  if [[ "$(dialect "$1")" == bash ]]; then bash_files+=("$1"); else sh_files+=("$1"); fi
}

while IFS= read -r -d '' f; do
  add "$f"
done < <(find hack -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)

templates=0
if [[ -d templates ]]; then
  while IFS= read -r -d '' t; do
    is_shell_template "$t" || continue
    rendered="$out/${t%.tftpl}.sh"
    mkdir -p "$(dirname "$rendered")"
    render "$t" >"$rendered"
    add "$rendered"
    templates=$((templates + 1))
  done < <(find templates -type f -name '*.tftpl' -print0 | sort -z)
fi

run() {
  local shell="$1"
  shift
  [[ $# -gt 0 ]] || return 0
  "$engine" run --rm --security-opt label=disable -v "$root:/work:ro" -w /work \
    "$image" shellcheck --shell="$shell" --external-sources "$@"
}

status=0
run sh "${sh_files[@]+"${sh_files[@]}"}" || status=1
run bash "${bash_files[@]+"${bash_files[@]}"}" || status=1

total=$((${#sh_files[@]} + ${#bash_files[@]}))
if [[ $status -ne 0 ]]; then
  echo "check-shell: shellcheck found problems (rendered templates are under $out/)" >&2
  exit 1
fi
echo "check-shell: ok ($total files, $templates rendered templates)"
