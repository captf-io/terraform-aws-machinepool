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

# The AWS provider, in the cluster's region (from exports). Only the region is
# set here: credentials come from the identity Secret through the SDK's
# default chain, never from module source (README "Identity Secret"). With
# no usable exports the region is null and AWS_REGION applies; a
# precondition on aws_autoscaling_group.pool_autoscaling_group then explains
# what is missing.
provider "aws" {
  region = local.cluster_exports.region
}
