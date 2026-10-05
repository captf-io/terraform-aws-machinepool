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

# What replaces the pool's instances: the Kubernetes version, verbatim (an
# RKE2 release bump, v1.31.4+rke2r1 to +rke2r2, is a version change too),
# and an explicit machine_image.id, since a pinned image carries the
# kubelet and must change with the version, possibly in another render. A
# looked-up image does not count: a re-published CAPA image would roll
# every pool. A change replaces this resource, which replaces the launch
# template (replace_triggered_by), whose new name starts an instance
# refresh. A bootstrap rotation, node labels or an instance type change
# reach new instances only (machinepool.md "Lifecycle"; README
# "Exceptions").
resource "terraform_data" "kubernetes_version_roll" {
  triggers_replace = {
    kubernetes_version = var.kubernetes_version
    machine_image_id   = var.machine_image.id
  }
}
