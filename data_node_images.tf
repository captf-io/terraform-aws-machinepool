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

# The AMIs matching machine_image's name format for this Kubernetes version,
# newest first; read only when machine_image.id is not set (locals_image.tf).
# The filters mirror the lookup of Cluster API Provider AWS
# (pkg/cloud/services/ec2/ami.go DefaultAMILookup).
data "aws_ami_ids" "node_images" {
  count = local.image_lookup_enabled ? 1 : 0

  # A deprecated image still boots; CAPA deprecates its images after a while.
  include_deprecated = true
  owners             = [var.machine_image.owner]

  filter {
    name   = "name"
    values = [local.image_name_filter]
  }
  filter {
    name   = "architecture"
    values = [var.machine_image.architecture]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}
