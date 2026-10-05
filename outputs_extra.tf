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

# Non-contract outputs, alphabetical. The controller never reads them; they
# tell operators which cloud objects back the pool and what the module left
# out of the kubelet's registration.

output "autoscaling_group_name" {
  description = "The Auto Scaling group's name."
  value       = local.group_name
}

output "dropped_node_labels" {
  description = "The node_labels left out of the kubelet's registration: kubernetes.io and k8s.io labels a kubelet may not set on itself."
  value       = local.dropped_node_labels
}

output "launch_template_id" {
  description = "The current launch template's ID. It changes only when the instances roll, on a Kubernetes version change."
  value       = try(aws_launch_template.pool_launch_template[0].id, null)
}
