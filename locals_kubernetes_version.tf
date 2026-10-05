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

# The Kubernetes version as image names and semver comparisons need it:
# without its v and without a distribution suffix such as +rke2r1, which the
# controller passes through verbatim (machinepool.md "kubernetes_version").
locals {
  kubernetes_semver  = var.kubernetes_version == null ? null : trimprefix(split("+", var.kubernetes_version)[0], "v")
  kubernetes_vsemver = local.kubernetes_semver == null ? null : "v${local.kubernetes_semver}"
}
