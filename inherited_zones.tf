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

# The zones a pool without MachinePool.spec.failureDomains inherits from the
# cluster, recorded at its first apply and kept (ignore_changes): a zone the
# cluster adds or drops later never moves running instances (CONVENTIONS.md
# section 13). Set failure_domains to change a pool's zones on purpose.
resource "terraform_data" "inherited_zones" {
  input = local.cluster_default_zones

  lifecycle {
    ignore_changes = [input]
  }
}
