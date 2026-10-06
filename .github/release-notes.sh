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

# release-notes.sh TAG prints the GitHub Release notes for module release
# TAG (vX.Y.Z or vX.Y.Z-rc.N) of this terraform-<provider>-<role> repo.
# Byte-identical in every terraform-* repo; ci.yml's release job runs it.
#
#   summary        the repo description, without its "Registry:" sentence
#   Upgrade notes  the annotated tag's message body, when it has one: write
#                  them when tagging (git tag -s vX.Y.Z, subject vX.Y.Z,
#                  then a blank line and Markdown bullets)
#   Using it       the module-images image and the Registry snippet
#   Changes        commit subjects since the previous tag ("First release."
#                  without one), and a compare link
#
# Needs the tag and its history, and gh (GH_TOKEN) for the description.
# GITHUB_REPOSITORY defaults to captf-io/<this directory's name>.
# The single-quoted printf formats hold literal Markdown backticks.
# shellcheck disable=SC2016
set -euo pipefail

tag="${1:?usage: release-notes.sh TAG}"
[[ "${tag}" =~ ^v([0-9]+)\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] ||
	{ echo "release-notes: ${tag} is not vX.Y.Z or vX.Y.Z-rc.N" >&2; exit 1; }
major="${BASH_REMATCH[1]}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"
repo="${GITHUB_REPOSITORY:-captf-io/$(basename "${root}")}"
name="${repo#*/}"
[[ "${name}" =~ ^terraform-([a-z]+)-(cluster|machine|machinepool)$ ]] ||
	{ echo "release-notes: ${name} is not terraform-<provider>-<role>" >&2; exit 1; }
provider="${BASH_REMATCH[1]}"
role="${BASH_REMATCH[2]}"
# module-images names Google Cloud gcp; the repos and the Registry say google.
image_cloud="${provider}"
[[ "${provider}" != google ]] || image_cloud=gcp

[[ "$(git cat-file -t "refs/tags/${tag}")" == tag ]] ||
	{ echo "release-notes: ${tag} is not an annotated tag (fetch it with --force)" >&2; exit 1; }

description="$(gh repo view "${repo}" --json description -q .description)"
description="${description%% Registry: *}"
# The contract version the module validates captf_contract against, at the
# tag (the noop modules don't validate it).
contract="$(git grep -h -o -E 'captf_contract == "v[0-9a-z]+"' "${tag}" -- '*.tf' | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
contract="${contract:-v1alpha1}"
status="Module image contract"
[[ "${major}" != 0 ]] || status="Pre-alpha, module image contract"

printf '## %s\n\n%s %s `%s`.\n\n' "${tag}" "${description}" "${status}" "${contract}"

upgrade="$(git tag -l --format='%(contents:body)' "${tag}" | sed -e '/^-----BEGIN SSH SIGNATURE-----$/,$d')"
if [[ -n "${upgrade//[[:space:]]/}" ]]; then
	printf '### Upgrade notes\n\n%s\n\n' "${upgrade}"
fi

cat <<EOF
### Using it

CAPTF runs the module from the image \`ghcr.io/captf-io/module-images/${image_cloud}-${role}:${tag}-<runtime>\` (\`terraform\` or \`opentofu\`), which module-images publishes once it picks up this release. The tag moves when the image is rebuilt (a base image update, for example), so pin the image by digest. Called directly from the Terraform Registry:

\`\`\`hcl
module "${role}" {
  source  = "captf-io/${role}/${provider}"
  version = "${tag#v}"
}
\`\`\`

### Changes

EOF

prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "${tag}^" 2>/dev/null || true)"
if [[ -z "${prev}" ]]; then
	printf -- '- First release.\n'
else
	# Dependabot's bumps are filtered by author; -P is for the lookahead.
	changes="$(git log --no-merges --perl-regexp --author='^(?!dependabot)' --format='- %s' "${prev}..${tag}")"
	printf '%s\n' "${changes:-- No changes besides dependency updates.}"
	printf '\nFull diff: https://github.com/%s/compare/%s...%s\n' "${repo}" "${prev}" "${tag}"
fi
