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

# What instances boot with (DESIGN.md "Bootstrap payloads are staged in S3",
# CONVENTIONS.md section 13). The payload is staged in S3 and rewritten in
# place on every rotation, so the launch template, and the instances, never
# change with it. The stub also renders node_labels into the kubelet's
# registration, since pool members have no Machine for CAPI to label.
locals {
  # "H4sI" is the base64 of the gzip magic (1f 8b 08). Whether the payload
  # is compressed is not secret.
  bootstrap_gzipped = nonsensitive(startswith(var.bootstrap_data, "H4sI"))

  # The payload object exists only when it can be written, with a bucket
  # from exports; otherwise a precondition on the group explains what is
  # missing.
  bootstrap_object_enabled = local.exports_complete
  bootstrap_bucket         = coalesce(local.cluster_exports.bootstrap_bucket, "-")

  # The kubelet refuses to start with a --node-labels label in the
  # kubernetes.io or k8s.io namespaces unless it is one it may set on itself
  # (IsKubeletLabel in k8s.io/kubelet pkg/apis/well_known_labels.go, checked
  # by the kubelet's options.go), and NodeRestriction enforces the same
  # list: those labels are dropped, the rest kept (machinepool.md
  # "node_labels").
  kubelet_labels = toset([
    "beta.kubernetes.io/arch",
    "beta.kubernetes.io/instance-type",
    "beta.kubernetes.io/os",
    "failure-domain.beta.kubernetes.io/region",
    "failure-domain.beta.kubernetes.io/zone",
    "kubernetes.io/arch",
    "kubernetes.io/hostname",
    "kubernetes.io/os",
    "node.kubernetes.io/instance-type",
    "topology.kubernetes.io/region",
    "topology.kubernetes.io/zone",
  ])
  node_label_prefixes = { for k in keys(var.node_labels) : k => length(split("/", k)) == 2 ? split("/", k)[0] : "" }
  node_labels = {
    for k, v in var.node_labels : k => v
    if contains(local.kubelet_labels, k) || !anytrue([
      for ns in ["kubernetes.io", "k8s.io"] : local.node_label_prefixes[k] == ns || endswith(local.node_label_prefixes[k], ".${ns}")
      ]) || anytrue([
      for ns in ["kubelet.kubernetes.io", "node.kubernetes.io"] : local.node_label_prefixes[k] == ns || endswith(local.node_label_prefixes[k], ".${ns}")
    ])
  }
  dropped_node_labels = sort(setsubtract(keys(var.node_labels), keys(local.node_labels)))
  node_label_list     = [for k in sort(keys(local.node_labels)) : "${k}=${local.node_labels[k]}"]

  # cloud-config: a boothook that writes the node labels, then downloads
  # the payload and installs it in /etc/cloud/cloud.cfg.d, which cloud-init
  # reads after its boothooks (DESIGN.md decision 1). Ignition: a config
  # that replaces itself with the object (spec 3.0.0, which every Ignition
  # 2.x accepts); it carries no node labels (a precondition rejects them).
  bootstrap_stub = var.bootstrap_format == "ignition" ? jsonencode({
    ignition = {
      version = "3.0.0"
      config  = { replace = { source = "s3://${local.bootstrap_bucket}/${local.bootstrap_object_key}" } }
    }
    }) : templatefile("${path.module}/templates/user_data.tftpl", {
    bucket      = local.bootstrap_bucket
    key         = local.bootstrap_object_key
    node_labels = join(",", local.node_label_list)
    region      = coalesce(local.cluster_exports.region, "-")
  })

  # EC2 limits user data to 16 KiB before base64
  # (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html).
  user_data_bytes     = length(local.bootstrap_stub)
  user_data_max_bytes = 16384
}
