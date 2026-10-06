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

# The pool: one Auto Scaling group across the pool's zones. It is the role's
# primary resource and holds its preconditions.
#
# desired_capacity is set at creation and then ignored: with autoscaling the
# scaling policy (autoscaler native) or a scaler outside the module
# (autoscaler external) owns it, and a fixed-size pool pins min_size and max_size
# to replicas instead, which moves the desired capacity with them
# (UpdateAutoScalingGroup: a new minimum above, or maximum below, the
# desired capacity resets it; machinepool.md "Module note").
resource "aws_autoscaling_group" "pool_autoscaling_group" {
  # count = 1, not a bare resource: once a refresh drops a bare resource
  # from state its references read as unknown, which try() cannot catch, so
  # the outputs would go null; an empty tuple fails the index, and try()
  # falls back (checked on Terraform 1.16.4 and OpenTofu 1.12.6).
  count = 1

  # Replace an instance at elevated risk of Spot interruption early.
  capacity_rebalance = var.spot
  desired_capacity   = var.replicas
  health_check_type  = "EC2"
  max_size           = var.autoscaling.enabled ? var.autoscaling.max : var.replicas
  min_size           = var.autoscaling.enabled ? var.autoscaling.min : var.replicas
  name               = local.group_name
  # Without AZRebalance, a zone added to failure_domains gets new instances
  # over time instead of running ones being terminated, undrained, to even
  # out the zones. Removing a zone still replaces the instances in it.
  # Zones inherited from the cluster never change (inherited_zones.tf).
  suspended_processes = ["AZRebalance"]
  vpc_zone_identifier = local.subnet_ids
  # Membership is the refresh loop's job: an apply that waited for capacity
  # and timed out would taint the group, and the next apply replace it.
  wait_for_capacity_timeout = "0"

  # A new launch template (a Kubernetes version change) starts a rolling refresh that launches each
  # replacement before terminating the instance it replaces. A refresh never
  # starts for a new version of the same template under $Latest
  # (https://registry.terraform.io/providers/hashicorp/aws/6.67.0/docs/resources/autoscaling_group#instance_refresh).
  instance_refresh {
    strategy = "Rolling"

    preferences {
      instance_warmup        = tostring(var.rollout_instance_warmup_seconds)
      max_healthy_percentage = 200
      min_healthy_percentage = 100
    }
  }

  # By name, which name_prefix makes new for every replaced template, so a
  # replacement changes this block and starts the refresh above.
  launch_template {
    name    = aws_launch_template.pool_launch_template[0].name
    version = "$Latest"
  }

  # Tags on the group itself; instances get theirs from the launch template.
  dynamic "tag" {
    for_each = local.tags

    content {
      key                 = tag.key
      propagate_at_launch = false
      value               = tag.value
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]

    precondition {
      condition     = local.exports_complete || !local.externally_managed || var.external_cluster_exports != null
      error_message = "The TerraformCluster is externally managed (captf_cluster_outputs is {}): set spec.variables.external_cluster_exports on the TerraformMachinePool to the cluster's exports (README \"Exports\")."
    }
    precondition {
      condition     = local.exports_complete || (local.externally_managed && var.external_cluster_exports == null)
      error_message = "The cluster's exports lack ${join(", ", local.exports_missing)}: ${local.externally_managed ? "external_cluster_exports" : "captf_cluster_outputs"} must hold every field of captf.io/aws-cluster/v1 (README \"Exports\")."
    }
    precondition {
      condition     = length(local.unknown_zones) == 0 || !local.exports_complete
      error_message = "failure_domains names zones that are not failure domains of the cluster: ${join(", ", local.unknown_zones)} (the cluster has ${join(", ", local.cluster_zones)}). Set MachinePool.spec.failureDomains to zones the cluster has subnets in."
    }
    precondition {
      condition     = !(var.bootstrap_format == "ignition" && length(local.node_labels) > 0)
      error_message = "Node labels need a cloud-config bootstrap: with Ignition the module cannot register them with the kubelet. Remove the labels from MachinePool.spec.template.metadata.labels, or use cloud-config."
    }
    precondition {
      condition     = !(var.bootstrap_format == "ignition" && local.bootstrap_gzipped)
      error_message = "A gzip-compressed Ignition payload cannot be staged in S3: Ignition cannot fetch a compressed config from s3://. Turn off gzipUserData in the bootstrap config."
    }
    precondition {
      condition     = local.user_data_bytes <= local.user_data_max_bytes
      error_message = "The user data is ${local.user_data_bytes} bytes, over EC2's ${local.user_data_max_bytes}-byte limit: the node labels make the stub too long; remove some labels."
    }
  }
}
