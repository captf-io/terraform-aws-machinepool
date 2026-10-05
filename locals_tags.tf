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

# Tags for every taggable resource (CONVENTIONS.md section 7). AWS accepts the
# captf.io/<key> keys unchanged; they merge last so additional_tags cannot
# override them.
locals {
  captf_tags = { for k, v in var.captf_tags : k => v }

  # cloud-provider-aws reads its cluster ID from this tag on its own
  # instance, and only manages instances that carry it.
  cloud_tags = {
    for id in [local.cluster_exports.kubernetes_cluster_id] : "kubernetes.io/cluster/${id}" => "owned" if id != null
  }

  tags = merge(var.additional_tags, local.cloud_tags, local.captf_tags)
}
