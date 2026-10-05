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

# Contract outputs of the machinepool role, in contract order:
# https://captf.io/docs/module-author/contract/v1alpha1/machinepool.html#outputs
# and "health" in https://captf.io/docs/module-author/contract/v1alpha1/common.html
#
# Every value reads refreshed state or data through try(), so an
# apply -refresh-only after the group vanished never errors.

output "provider_id" {
  description = "The Auto Scaling group's ARN."
  value       = try(aws_autoscaling_group.pool_autoscaling_group[0].arn, null)
}

output "provider_id_list" {
  description = "aws:///<availability-zone>/<instance-id> of every non-terminated member, whatever its state or health: the providerIDs cloud-provider-aws writes to the Nodes."
  value       = sort(distinct(local.member_provider_ids))
}

output "replicas" {
  description = "The group's desired capacity as last observed, not a count of running instances; replicas while the group is gone, so the controller never writes back a 0 it did not observe."
  value       = try(aws_autoscaling_group.pool_autoscaling_group[0].desired_capacity, var.replicas)
}

output "instances" {
  description = "Every member: provider and instance ID, private IP, zone and health state."
  value = [
    for p in sort(local.member_provider_ids) : {
      provider_id    = p
      instance_id    = local.members_by_provider_id[p].instance_id
      addresses      = local.members_by_provider_id[p].private_ip == null ? [] : [{ type = "InternalIP", address = local.members_by_provider_id[p].private_ip }]
      failure_domain = local.members_by_provider_id[p].zone
      state          = local.member_health[p].state
    }
  ]
}

output "health" {
  description = "running/healthy at zero replicas; pending until the first member exists; otherwise the worst member state (stopped, unknown), healthy only when every member runs and the member count equals the desired capacity."
  value       = local.health_reading
}
