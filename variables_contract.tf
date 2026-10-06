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

# Contract inputs of the machinepool role, in contract order, with the
# contract's types: https://captf.io/docs/module-author/contract/v1alpha1/common.html
# and https://captf.io/docs/module-author/contract/v1alpha1/machinepool.html

# Only its validation reads it: the module asserts the contract version.
# tflint-ignore: terraform_unused_declarations
variable "captf_contract" {
  description = "Contract version the controller generated the root for; always v1alpha1."
  type        = string

  validation {
    condition     = var.captf_contract == "v1alpha1"
    error_message = "captf_contract must be v1alpha1: this module implements the v1alpha1 machinepool role."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "captf_cluster" {
  description = "The owning CAPI Cluster: name and namespace."
  type = object({
    name      = string
    namespace = string
  })
}

variable "captf_object" {
  description = "The TerraformMachinePool being reconciled: kind, name and namespace."
  type = object({
    kind      = string
    name      = string
    namespace = string
  })
}

variable "captf_cluster_outputs" {
  description = "The cluster role's exports (schema captf.io/aws-cluster/v1), or {} for an externally managed TerraformCluster, which then needs external_cluster_exports."
  type        = any

  validation {
    condition     = contains(["{}", "null"], jsonencode(var.captf_cluster_outputs)) || try(var.captf_cluster_outputs.schema == "captf.io/aws-cluster/v1", false)
    error_message = "captf_cluster_outputs must be the exports of the aws cluster module (schema captf.io/aws-cluster/v1): the cluster runs a different module or an incompatible version."
  }
}

variable "captf_tags" {
  description = "Tags the controller always sets (captf.io/cluster, captf.io/namespace, captf.io/kind, captf.io/name, captf.io/managed-by, captf.io/template); applied to every taggable resource."
  type        = map(string)
}

variable "machinepool_name" {
  description = "The owning CAPI MachinePool's name: part of the group's name and the key of its bootstrap object."
  type        = string
}

variable "replicas" {
  description = "The group's desired capacity. With autoscaling enabled, the controller renders the observed capacity clamped into [min, max], and the module sets it only when the group is created."
  type        = number

  validation {
    condition     = var.replicas >= 0 && floor(var.replicas) == var.replicas
    error_message = "replicas must be a whole number of at least 0."
  }
}

variable "bootstrap_data" {
  description = "Base64 of the bootstrap Secret's value. Staged in S3 and rewritten in place on every rotation, never parsed."
  type        = string
  sensitive   = true
}

variable "bootstrap_format" {
  description = "The bootstrap payload's format: cloud-config or ignition."
  type        = string

  validation {
    condition     = contains(["cloud-config", "ignition"], var.bootstrap_format)
    error_message = "bootstrap_format must be cloud-config or ignition."
  }
}

variable "failure_domains" {
  description = "MachinePool.spec.failureDomains: the availability zones to spread over. Empty means every zone of the cluster."
  type        = list(string)
}

variable "cluster_failure_domains" {
  description = "The cluster's failure-domain names, read from the cluster's state: the zones an empty failure_domains spreads over."
  type        = list(string)
}

variable "kubernetes_version" {
  description = "MachinePool.spec.template.spec.version (vX.Y.Z, or vX.Y.Z+rke2rN under RKE2). A change rolls every instance; it also selects the default AMI."
  type        = string
  default     = null
}

variable "node_labels" {
  description = "MachinePool.spec.template.metadata.labels. Rendered into the kubelet's --node-labels at boot, less the kubernetes.io and k8s.io labels the kubelet may not set on itself."
  type        = map(string)

  validation {
    # Kubernetes label syntax; the user-data stub relies on it to quote the
    # labels safely.
    condition = alltrue([
      for k, v in var.node_labels :
      can(regex("^([a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*/)?[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$", k)) &&
      length(split("/", k)[0]) <= 253 &&
      can(regex("^([A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?)?$", v))
    ])
    error_message = "node_labels must hold Kubernetes labels: an optional DNS-subdomain prefix of at most 253 characters, then a name and a value of at most 63 characters from A-Z, a-z, 0-9, -, _ and ."
  }
}

variable "autoscaling" {
  description = "Parsed from the MachinePool's cluster-api-autoscaler-node-group-min-size and -max-size annotations. enabled hands the desired capacity to a target-tracking policy within [min, max], or to a scaler outside the module when autoscaler is external."
  type = object({
    enabled = bool
    min     = number
    max     = number
  })

  validation {
    condition     = !var.autoscaling.enabled || (var.autoscaling.min >= 0 && var.autoscaling.min <= var.autoscaling.max)
    error_message = "autoscaling must have 0 <= min <= max when enabled."
  }
}
