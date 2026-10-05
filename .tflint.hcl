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

# tflint configuration for the module. `make tflint` runs it in the pinned
# tflint container; plugins are cached under .cache/tflint.
#
# A ruleset upgrade is its own commit: bump the version here, run
# `make tflint`, fix or justify what it finds.

plugin "terraform" {
  enabled = true
  preset  = "all"
  version = "0.15.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"

  # Rules that need credentials and API calls stay off: the checks must run
  # offline in CI. (Recent rulesets no longer have deep checking at all.)
  deep_check = false
}

# CONVENTIONS.md section 2 lays the files out differently on purpose: one
# resource or data block per file, named after the block, and the fixed files
# versions.tf, providers.tf, variables*.tf, outputs*.tf and locals_*.tf.
# hack/check-layout.sh enforces that layout instead.
rule "terraform_standard_module_structure" {
  enabled = false
}
