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

# With autoscaling enabled and autoscaler native, a target-tracking policy
# owns the group's desired capacity within [autoscaling.min, autoscaling.max]
# (machinepool.md "autoscaling"). With autoscaler external there is no
# policy: a scaler outside the module sets the capacity within the same
# bounds. Scale-in terminates instances without draining their nodes
# (README "Limitations").
resource "aws_autoscaling_policy" "pool_scaling_policy" {
  count = var.autoscaling.enabled && var.autoscaler == "native" ? 1 : 0

  autoscaling_group_name = aws_autoscaling_group.pool_autoscaling_group[0].name
  name                   = "captf-cpu-target-tracking"
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value = var.autoscaling_target_cpu_percent

    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}
