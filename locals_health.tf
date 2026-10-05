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

# Pool health from the group and its members ("health" in
# https://captf.io/docs/module-author/contract/v1alpha1/common.html,
# machinepool.md "Per-instance state", CONVENTIONS.md section 10). Pool
# health feeds conditions only; nothing remediates pool instances.
locals {
  # A counted resource that a refresh dropped reads as an empty tuple; the
  # length is known at plan time too, unlike the group's attributes.
  group_exists     = length(aws_autoscaling_group.pool_autoscaling_group) > 0
  desired_capacity = try(aws_autoscaling_group.pool_autoscaling_group[0].desired_capacity, var.replicas)

  # Member state (locals_membership.tf) -> contract health. Members are
  # never shutting-down or terminated: the membership read leaves those out.
  health_by_state = {
    pending = { state = "pending", reason = "InstancePending" }
    running = { state = "running", reason = null }
    stopped = { state = "stopped", reason = "InstanceStopped" }
  }
  member_health = {
    for p, m in local.members_by_provider_id : p => lookup(local.health_by_state, m.state, { state = "unknown", reason = "UnknownState" })
  }

  # The worst member state, in the order degraded, stopped, unknown. A
  # pending (starting) member does not make the pool pending: the contract
  # keeps pending for a group with no members at all, and the controller
  # already refreshes every 30 s while the member count differs from the
  # desired capacity (machinepool.md "Per-instance state").
  worst_member_state = try([for s in ["degraded", "stopped", "unknown"] : s if contains([for h in values(local.member_health) : h.state], s)][0], null)
  # "<Reason>:<instance-id>" for every member that is not running.
  unready_members = sort([for p, h in local.member_health : "${h.reason}:${local.members_by_provider_id[p].instance_id}" if h.reason != null])
  member_count    = length(local.members)

  health_reading = (
    !local.group_exists ? {
      state   = "terminated"
      healthy = false
      message = "Auto Scaling group ${local.group_name} not found"
      reasons = ["GroupNotFound"]
    } :
    local.desired_capacity == 0 ? {
      state   = "running"
      healthy = true
      message = "the group is scaled to zero"
      reasons = []
    } :
    local.member_count == 0 ? {
      state   = "pending"
      healthy = false
      message = "waiting for the first of ${local.desired_capacity} instances"
      reasons = ["NoMembers"]
    } :
    local.worst_member_state != null ? {
      state   = local.worst_member_state
      healthy = false
      message = "${local.member_count} of ${local.desired_capacity} instances, not all running: ${join(", ", local.unready_members)}"
      reasons = local.unready_members
    } :
    {
      state   = "running"
      healthy = length(local.unready_members) == 0 && local.member_count == local.desired_capacity
      message = "${local.member_count - length(local.unready_members)} of ${local.desired_capacity} instances running"
      reasons = concat(local.unready_members, local.member_count == local.desired_capacity ? [] : ["ScalingInProgress"])
    }
  )
}
