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

# The group's members, one read per cluster zone so each member's zone (part
# of its provider ID) is known. Every zone of the cluster, not only the
# pool's: an instance left in a zone the pool no longer uses is still a
# member until the group terminates it. Every state short of shutting-down
# and terminated counts, whatever its health: CAPI deletes the Node of a
# provider ID that leaves provider_id_list (machinepool.md
# "provider_id_list").
#
# The filter uses the group's name, which is known before the group exists,
# so the read happens at plan time and a refresh re-reads it.
data "aws_instances" "pool_members" {
  for_each = toset(local.cluster_zones)

  instance_state_names = ["pending", "running", "stopping", "stopped"]

  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [local.group_name]
  }
  filter {
    name   = "availability-zone"
    values = [each.key]
  }
}
