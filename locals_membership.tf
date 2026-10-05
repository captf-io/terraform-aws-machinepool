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

# The group's members as the contract reports them (machinepool.md
# "provider_id_list", "instances"), from the membership reads. Refreshed on
# every apply -refresh-only, which the controller runs every
# membershipRefreshIntervalSeconds.
locals {
  running_member_ids = toset(data.aws_instances.pool_running_members.ids)
  stopped_member_ids = toset(data.aws_instances.pool_stopped_members.ids)

  # A member's state: running, stopping/stopped, or else pending (a member
  # is pending, running, stopping or stopped). An instance that changes
  # state between the reads reads as pending for one refresh.
  members = flatten([
    for zone, read in data.aws_instances.pool_members : [
      for i, id in read.ids : {
        instance_id = id
        zone        = zone
        provider_id = "aws:///${zone}/${id}"
        state       = contains(local.running_member_ids, id) ? "running" : contains(local.stopped_member_ids, id) ? "stopped" : "pending"
        # private_ips lines up with ids only when every member has one,
        # which every VPC instance does from launch.
        private_ip = length(read.private_ips) == length(read.ids) ? read.private_ips[i] : null
      }
    ]
  ])
  members_by_provider_id = { for m in local.members : m.provider_id => m }
  member_provider_ids    = keys(local.members_by_provider_id)
}
