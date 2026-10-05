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

# Names of what the pool creates, derived from the pool's key with a hash that
# keeps truncated names unique (CONVENTIONS.md section 6). The group name is
# ForceNew and must be known at plan time: the membership reads filter on it
# before the group exists.
locals {
  pool_key  = "${var.captf_object.namespace}/${var.machinepool_name}"
  pool_hash = substr(sha256(local.pool_key), 0, 8)
  name_base = replace(lower("captf-${var.captf_object.namespace}-${var.machinepool_name}"), "/[^a-z0-9-]/", "-")

  # At most 63 characters: 63 - 9 leaves room for "-" and the hash.
  group_name = "${trimsuffix(substr(local.name_base, 0, 63 - 9), "-")}-${local.pool_hash}"
  # Launch templates are replaced create-before-destroy on a roll, so their
  # names are generated from this prefix.
  launch_template_name_prefix = "${local.group_name}-"

  # The instances' Name tag, for people: Kubernetes knows a node by its
  # private DNS name.
  instance_name = var.machinepool_name

  # The payload's key in the bootstrap bucket: pool/ is readable by worker
  # nodes (cluster/locals_bootstrap.tf).
  bootstrap_object_key = "pool/${var.machinepool_name}"
}
