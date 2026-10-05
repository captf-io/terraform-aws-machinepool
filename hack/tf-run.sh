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

# Run one Terraform or OpenTofu action on the module (the repository root)
# in a container pinned by digest. The Makefile and check-tags.sh call this;
# run it by hand to reproduce one cell of `make validate` or `make unit-test`.
#
# Usage: hack/tf-run.sh <action> <terraform|opentofu> <image|default> [args...]
#
# Actions:
#   fmt        fmt -recursive in place (the module, its templates and tests)
#   fmt-check  fmt -recursive -check -diff
#   validate   init -backend=false, then validate [args]
#   test       init -backend=false, then test [args]
#   schema     init, then write `providers schema -json` to
#              build/schema/<runtime>.json
#
# <image> is a full image reference, or `default` for the pinned runtime
# image in $TF_IMAGE_<runtime> (the Makefile exports both; `make
# print-TF_IMAGE_terraform` prints one). Everything but fmt runs on a copy
# of the module in build/stage/: the *.tf files, templates/ and tests/. No
# lock file is committed (CONVENTIONS.md section 5), so init resolves the
# exact provider pins of versions.tf afresh and the staged lock file is
# thrown away with the stage. Provider downloads are cached under
# .cache/plugins/<runtime>. Runs serially: the caches are not safe for
# concurrent writers.
#
# Env: ENGINE (podman|docker, default podman),
#      TF_IMAGE_terraform, TF_IMAGE_opentofu (the images for `default`),
#      NO_TESTS=1 (leave tests/ out of the staged copy: OpenTofu 1.6 reads
#      *.tftest.hcl at init and fails on mock_provider, which it predates).
set -euo pipefail

usage="usage: tf-run.sh <fmt|fmt-check|validate|test|schema> <terraform|opentofu> <image|default> [args...]"
action=${1:?$usage}
runtime=${2:?$usage}
image=${3:?$usage}
shift 3

engine=${ENGINE:-podman}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

case $runtime in
  terraform) bin=terraform ;;
  opentofu) bin=tofu ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
[[ -f versions.tf ]] || { echo "tf-run.sh: versions.tf not found at the repository root" >&2; exit 2; }

if [[ $image == default ]]; then
  var=TF_IMAGE_$runtime
  image=${!var:-}
  [[ -n $image ]] || { echo "tf-run.sh: $var is not set; run through make, or set it to an image" >&2; exit 2; }
fi

case $engine in
  docker) user_flags=(--user "$(id -u):$(id -g)") ;;
  # The images set USER 65532, which wins over keep-id's default, so the
  # user is explicit; keep-id maps it to the host user for file ownership.
  *) user_flags=(--userns=keep-id --user "$(id -u):$(id -g)") ;;
esac

# container_run <workdir-under-/work> <script> [args...]: the script runs
# under sh with the repository mounted at /work, as the host user.
container_run() {
  local workdir=$1 script=$2
  shift 2
  "$engine" run --rm "${user_flags[@]}" --security-opt label=disable \
    -e HOME=/tmp -e CHECKPOINT_DISABLE=1 -e TF_IN_AUTOMATION=1 -e TF_INPUT=0 \
    -e "TF_PLUGIN_CACHE_DIR=/work/.cache/plugins/$runtime" \
    -v "$root:/work" -w "/work/$workdir" --entrypoint /bin/sh \
    "$image" -euc "$script" sh "$@"
}

# Every action, fmt included, points TF_PLUGIN_CACHE_DIR here, and the
# runtimes refuse a cache directory that does not exist (a fresh clone).
mkdir -p ".cache/plugins/$runtime"

# The paths fmt looks at: the module files and the test files. hack/testdata
# holds deliberately bad fixtures and is never formatted.
fmt_paths=(.)
[[ -d tests ]] && fmt_paths+=(tests)

case $action in
  fmt)
    echo "--- $action: module on $runtime (${image%%@*})"
    container_run . "for p; do $bin fmt -no-color \"\$p\"; done" "${fmt_paths[@]}"
    exit 0
    ;;
  fmt-check)
    echo "--- $action: module on $runtime (${image%%@*})"
    container_run . "rc=0; for p; do $bin fmt -check -diff -no-color \"\$p\" || rc=1; done; exit \$rc" "${fmt_paths[@]}"
    exit 0
    ;;
  validate | test | schema) ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

# Stage the module. The label keeps stages of different images apart.
label=$(printf '%s' "${image%%@*}" | tr -c 'A-Za-z0-9._\n-' '_')
stage="build/stage/$runtime-$label/module"
case $stage in
  build/stage/?*/module) ;;
  *) echo "tf-run.sh: refusing to stage into '$stage'" >&2; exit 1 ;;
esac
if [[ -e $stage ]]; then
  [[ -d $stage && ! -L $stage ]] || { echo "tf-run.sh: $stage is not a directory" >&2; exit 1; }
  rm -rf -- "$stage"
fi
mkdir -p "$stage" build/schema
cp -- ./*.tf "$stage/"
[[ ! -d templates ]] || cp -R -- templates "$stage/"
[[ -n ${NO_TESTS:-} || ! -d tests ]] || cp -R -- tests "$stage/"

init="$bin init -backend=false -input=false -no-color"
echo "--- $action: module on $runtime (${image%%@*})"
case $action in
  validate)
    container_run "$stage" "$init && $bin validate -no-color \"\$@\"" "$@"
    ;;
  test)
    container_run "$stage" "$init && $bin test -no-color \"\$@\"" "$@"
    ;;
  schema)
    out="build/schema/$runtime.json"
    container_run "$stage" "$init >/dev/null && $bin providers schema -json > /work/$out"
    echo "wrote $out"
    ;;
esac
