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

# The AMI: machine_image.id, else the newest AMI matching the name format for
# this Kubernetes version (the Cluster API Provider AWS convention,
# https://cluster-api-aws.sigs.k8s.io/topics/images/amis.html).
locals {
  image_lookup_enabled = var.machine_image.id == null && local.kubernetes_semver != null
  image_name_filter    = local.kubernetes_semver == null ? null : replace(replace(var.machine_image.name_format, "{semver}", local.kubernetes_semver), "{version}", local.kubernetes_vsemver)

  # aws_ami_ids lists the matches newest first and returns none, rather than
  # failing, when the image is gone, so a membership refresh never fails on
  # a deregistered AMI; the precondition on
  # aws_launch_template.pool_launch_template reports a missing image on the
  # next apply.
  image_id = var.machine_image.id != null ? var.machine_image.id : try(data.aws_ami_ids.node_images[0].ids[0], null)
}
