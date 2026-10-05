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

# User variables of the machinepool role, alphabetical. Set them through
# TerraformMachinePool spec.variables or spec.variablesFrom
# (https://captf.io/docs/user-guide/variables.html). They are mutable: a
# change updates the launch template, and new instances get it; only a
# kubernetes_version change replaces running instances.

variable "additional_security_group_ids" {
  description = "Extra security groups for the instance, on top of the cluster's (for example one that admits SSH from a bastion)."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.additional_security_group_ids : startswith(s, "sg-")])
    error_message = "additional_security_group_ids must hold security group IDs (sg-...)."
  }
}

variable "additional_tags" {
  description = "Extra tags for every taggable resource. The captf tags are merged last and win, so these cannot override them."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    # 50 tags per AWS resource, less the captf tags (6) and the module's own
    # (Name, kubernetes.io/cluster/<id>), with headroom.
    condition     = length(var.additional_tags) <= 40
    error_message = "additional_tags holds at most 40 tags: AWS allows 50 per resource and the module sets up to 8 itself."
  }
  validation {
    condition = alltrue([
      for k, v in var.additional_tags :
      length(k) >= 1 && length(k) <= 128 && length(v) <= 256
    ])
    error_message = "additional_tags must have keys of 1 to 128 characters and values of at most 256 characters, the AWS tag limits."
  }
  validation {
    # The tag character set IAM, Elastic Load Balancing and Auto Scaling
    # enforce, the strictest of the services tagged here.
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]*$", k)) && can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]*$", v))])
    error_message = "additional_tags must use only letters, numbers, spaces and _ . : / = + - @ in keys and values, the AWS tag character set."
  }
  validation {
    condition = alltrue([
      for k in keys(var.additional_tags) :
      !startswith(lower(k), "aws:") && !startswith(k, "captf.io/") && !startswith(k, "kubernetes.io/cluster/")
    ])
    error_message = "additional_tags must not use the aws: prefix (reserved by AWS), captf.io/ (the captf tags) or kubernetes.io/cluster/ (the cluster ownership tag)."
  }
}

variable "autoscaling_target_cpu_percent" {
  description = "Average CPU utilization the target-tracking policy keeps the group at while autoscaling is enabled. CPU is a proxy: pods waiting for capacity do not raise it."
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition     = var.autoscaling_target_cpu_percent > 0 && var.autoscaling_target_cpu_percent <= 100
    error_message = "autoscaling_target_cpu_percent must be greater than 0 and at most 100."
  }
}

variable "external_cluster_exports" {
  description = "The exports of an externally managed TerraformCluster (schema captf.io/aws-cluster/v1, README \"Exports\"), used only when captf_cluster_outputs is {}."
  type        = any
  default     = null

  validation {
    condition     = var.external_cluster_exports == null || try(var.external_cluster_exports.schema == "captf.io/aws-cluster/v1", false)
    error_message = "external_cluster_exports must follow the exports schema captf.io/aws-cluster/v1 (README \"Exports\"), including schema = \"captf.io/aws-cluster/v1\"."
  }
}

variable "instance_metadata_hop_limit" {
  description = "IMDSv2 response hop limit. 1 keeps the node's credentials away from pods without host networking; 2 lets such pods (for example the EBS CSI controller) reach the instance metadata service."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.instance_metadata_hop_limit >= 1 && var.instance_metadata_hop_limit <= 64 && floor(var.instance_metadata_hop_limit) == var.instance_metadata_hop_limit
    error_message = "instance_metadata_hop_limit must be a whole number from 1 to 64."
  }
}

variable "instance_type" {
  description = "EC2 instance type of the group's instances. A change applies to instances launched afterwards; running ones keep theirs until replaced (scale-in, a Kubernetes version change)."
  type        = string
  default     = "m6i.large"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9-]+$", var.instance_type))
    error_message = "instance_type must be an EC2 instance type such as m6i.large."
  }
}

variable "machine_image" {
  description = "The AMI. Set id in production. Without it, the newest AMI named name_format from owner is used, with {semver} replaced by the Kubernetes version without its v and any +suffix (1.31.4) and {version} by the version without the suffix (v1.31.4): by default the Cluster API Provider AWS images, which are built for testing, not production. root_device_name is the image's root device, which the launch template sizes and encrypts: /dev/sda1 for Ubuntu and the CAPA images, /dev/xvda for Amazon Linux and Flatcar. Changing id rolls the instances, since the image carries the kubelet."
  type = object({
    id               = optional(string)
    owner            = optional(string, "819546954734")
    name_format      = optional(string, "capa-ami-ubuntu-24.04-?{semver}-*")
    architecture     = optional(string, "x86_64")
    root_device_name = optional(string, "/dev/sda1")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.machine_image.id == null || can(regex("^ami-[0-9a-f]+$", coalesce(var.machine_image.id, "-")))
    error_message = "machine_image.id must be an AMI ID (ami-...) or null."
  }
  validation {
    condition     = strcontains(var.machine_image.name_format, "{semver}") || strcontains(var.machine_image.name_format, "{version}")
    error_message = "machine_image.name_format must hold {semver} or {version}, where the Kubernetes version goes."
  }
  validation {
    condition     = contains(["x86_64", "arm64"], var.machine_image.architecture)
    error_message = "machine_image.architecture must be x86_64 or arm64."
  }
  validation {
    condition     = can(regex("^([0-9]{12}|self|amazon|aws-marketplace)$", var.machine_image.owner))
    error_message = "machine_image.owner must be an AWS account ID or one of self, amazon and aws-marketplace."
  }
  validation {
    condition     = can(regex("^/dev/[a-z0-9]+$", var.machine_image.root_device_name))
    error_message = "machine_image.root_device_name must be a device name such as /dev/sda1 or /dev/xvda."
  }
}

variable "public_ip" {
  description = "Give the instance a public IPv4 address. Off by default: nodes reach the internet through the network's NAT or endpoints."
  type        = bool
  default     = false
  nullable    = false
}

variable "rollout_instance_warmup_seconds" {
  description = "Seconds an instance refresh waits after a new instance is in service before counting it healthy and replacing the next one: time for the node to boot and join."
  type        = number
  default     = 300
  nullable    = false

  validation {
    condition     = var.rollout_instance_warmup_seconds >= 0 && floor(var.rollout_instance_warmup_seconds) == var.rollout_instance_warmup_seconds
    error_message = "rollout_instance_warmup_seconds must be a whole number of at least 0."
  }
}

variable "root_volume_kms_key_id" {
  description = "ARN of the KMS key to encrypt the root volumes with. Null uses the account's default EBS key; the volumes are always encrypted. A customer managed key must grant the AWSServiceRoleForAutoScaling service-linked role, or launches fail with Client.InvalidKMSKey.InvalidState."
  type        = string
  default     = null

  validation {
    condition     = var.root_volume_kms_key_id == null || can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/", coalesce(var.root_volume_kms_key_id, "-")))
    error_message = "root_volume_kms_key_id must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>) or null."
  }
}

variable "root_volume_size_gib" {
  description = "Root volume size in GiB: room for the OS, container images and logs."
  type        = number
  default     = 40
  nullable    = false

  validation {
    condition     = var.root_volume_size_gib >= 8 && var.root_volume_size_gib <= 16384 && floor(var.root_volume_size_gib) == var.root_volume_size_gib
    error_message = "root_volume_size_gib must be a whole number from 8 to 16384."
  }
}

variable "root_volume_type" {
  description = "EBS volume type of the root volume: gp3 (baseline 3000 IOPS) or gp2. Provisioned-IOPS types need an IOPS setting this module does not expose."
  type        = string
  default     = "gp3"
  nullable    = false

  validation {
    condition     = contains(["gp2", "gp3"], var.root_volume_type)
    error_message = "root_volume_type must be gp3 or gp2."
  }
}

variable "spot" {
  description = "Launch Spot Instances, with capacity rebalancing so the group replaces an instance at elevated interruption risk before it is reclaimed. Nothing drains the node first (README \"Limitations\")."
  type        = bool
  default     = false
  nullable    = false
}

variable "ssh_key_name" {
  description = "EC2 key pair for SSH. Null sets none; no security group rule admits SSH either way (use additional_security_group_ids, or SSM Session Manager)."
  type        = string
  default     = null
}
