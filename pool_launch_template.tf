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

# What the group launches. Every change makes a new version, which becomes the
# default (update_default_version) and which the group launches from
# ($Latest): new instances get it, running ones keep theirs. Only a
# Kubernetes version change (terraform_data.kubernetes_version_roll) replaces the
# template itself, and the new template starts an instance refresh.
resource "aws_launch_template" "pool_launch_template" {
  # count = 1, like the group: a bare resource dropped from state on refresh
  # reads as unknown, which try() in outputs cannot catch.
  count = 1

  description            = "CAPTF machine pool ${local.pool_key}"
  image_id               = local.image_id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  name_prefix            = local.launch_template_name_prefix
  tags                   = local.tags
  update_default_version = true
  user_data              = base64encode(local.bootstrap_stub)

  block_device_mappings {
    device_name = var.machine_image.root_device_name

    ebs {
      delete_on_termination = "true"
      encrypted             = "true"
      kms_key_id            = var.root_volume_kms_key_id
      volume_size           = var.root_volume_size_gib
      volume_type           = var.root_volume_type
    }
  }

  iam_instance_profile {
    name = local.instance_profile
  }

  dynamic "instance_market_options" {
    for_each = var.spot ? [true] : []

    content {
      market_type = "spot"
    }
  }

  # IMDSv2 only. Instance tags stay out of the metadata service: their keys
  # contain "/", which IMDS does not allow
  # (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/work-with-tags-in-IMDS.html).
  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = var.instance_metadata_hop_limit
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  # An interface rather than vpc_security_group_ids, so the public IP
  # setting is explicit whatever the subnet's default.
  network_interfaces {
    associate_public_ip_address = tostring(var.public_ip)
    delete_on_termination       = "true"
    device_index                = 0
    security_groups             = local.security_group_ids
  }

  # Instances launched by Auto Scaling get their tags here; provider
  # default_tags would not reach them.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = local.instance_name })
  }
  tag_specifications {
    resource_type = "network-interface"
    tags          = local.tags
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = local.instance_name })
  }

  lifecycle {
    # The group still uses the old template until it points at the new one.
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.kubernetes_version_roll]

    precondition {
      condition     = local.image_id != null
      error_message = var.machine_image.id == null && local.kubernetes_semver == null ? "No AMI to boot: set spec.variables.machine_image.id, or set the MachinePool's version so an image can be looked up." : "No AMI named ${coalesce(local.image_name_filter, "-")} (architecture ${var.machine_image.architecture}) is owned by ${var.machine_image.owner} in this region: set machine_image.id, or a name_format and owner that match an image here."
    }
  }
}
