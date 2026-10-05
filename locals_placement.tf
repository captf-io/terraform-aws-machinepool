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

# Placement: the availability zones the group spreads over, their subnets, and
# the worker security groups and instance profile.
locals {
  cluster_zones = sort(keys(local.cluster_exports.failure_domains))

  # Every zone of the cluster (machinepool.md "cluster_failure_domains"),
  # as the cluster reports it today.
  cluster_default_zones = sort(length(var.cluster_failure_domains) > 0 ? var.cluster_failure_domains : local.cluster_zones)

  # MachinePool.spec.failureDomains, else the cluster's zones as recorded at
  # the pool's first apply (inherited_zones.tf), less any the cluster no
  # longer has a subnet in.
  requested_zones = sort(var.failure_domains)
  inherited_zones = [for z in sort(terraform_data.inherited_zones.output) : z if contains(local.cluster_zones, z)]
  zones           = length(var.failure_domains) > 0 ? local.requested_zones : local.inherited_zones
  unknown_zones   = sort(setsubtract(local.requested_zones, local.cluster_zones))
  subnet_ids      = [for z in local.zones : local.cluster_exports.failure_domains[z] if contains(local.cluster_zones, z)]

  instance_profile   = local.cluster_exports.worker_instance_profile
  security_group_ids = concat(local.cluster_exports.worker_security_group_ids, var.additional_security_group_ids)
}
