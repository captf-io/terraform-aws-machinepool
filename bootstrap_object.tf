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

# The bootstrap payload, staged in the cluster's bootstrap bucket for new
# instances to fetch (locals_bootstrap.tf). The kubeadm bootstrap provider
# rewrites a pool's token about every 7.5 minutes; each rotation updates
# this object in place, so the launch template and the running instances
# never change with it. content_base64 takes the payload as-is and S3
# stores the decoded bytes, so a gzip payload arrives intact.
resource "aws_s3_object" "bootstrap_object" {
  count = local.bootstrap_object_enabled ? 1 : 0

  bucket                 = local.cluster_exports.bootstrap_bucket
  content_base64         = var.bootstrap_data
  content_type           = "application/octet-stream"
  key                    = local.bootstrap_object_key
  server_side_encryption = "AES256"
  # S3 objects take at most 10 tags, so only the captf tags
  # (hack/tags.json).
  tags = local.captf_tags
}
