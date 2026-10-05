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

# One expect_failures run per variable validation of the machinepool role
# (CONVENTIONS.md section 14), each against an otherwise valid pool.

mock_provider "aws" {
  mock_data "aws_ami_ids" {
    defaults = {
      ids = ["ami-0123456789abcdef0"]
    }
  }
  mock_data "aws_instances" {
    defaults = {
      ids         = []
      private_ips = []
      public_ips  = []
    }
  }
}

variables {
  captf_contract = "v1alpha1"
  captf_cluster  = { name = "demo", namespace = "team-a" }
  captf_object   = { kind = "TerraformMachinePool", name = "demo-pool-0", namespace = "team-a" }
  captf_cluster_outputs = {
    schema                = "captf.io/aws-cluster/v1"
    region                = "us-east-1"
    vpc_id                = "vpc-0123456789abcdef0"
    kubernetes_cluster_id = "captf-team-a-demo-1960e37c"
    failure_domains       = { "us-east-1a" = { subnet_id = "subnet-0aaa0000000000001" } }
    security_group_ids    = { control_plane = ["sg-0c0000000000000c1", "sg-0e0000000000000e1"], worker = ["sg-0e0000000000000e1"] }
    instance_profiles     = { control_plane = "captf-team-a-demo-1960e37c-control-plane", worker = "captf-team-a-demo-1960e37c-worker" }
    api                   = null
    bootstrap_bucket      = "captf-bootstrap-20261001000000000000000001"
  }
  captf_tags              = { "captf.io/cluster" = "demo" }
  machinepool_name        = "demo-pool-0"
  replicas                = 2
  bootstrap_data          = "I2Nsb3VkLWNvbmZpZwpydW5jbWQ6IFtlY2hvIGhlbGxvXQo="
  bootstrap_format        = "cloud-config"
  failure_domains         = []
  cluster_failure_domains = ["us-east-1a"]
  kubernetes_version      = "v1.34.1"
  node_labels             = {}
  autoscaling             = { enabled = false, min = 0, max = 0 }
}

run "valid_baseline" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].desired_capacity == 2
    error_message = "the baseline every other run varies must plan."
  }
}

run "invalid_captf_contract" {
  command = plan

  variables {
    captf_contract = "v1beta1"
  }

  expect_failures = [var.captf_contract]
}

run "invalid_replicas" {
  command = plan

  variables {
    replicas = -1
  }

  expect_failures = [var.replicas]
}

run "invalid_bootstrap_format" {
  command = plan

  variables {
    bootstrap_format = "cloud-init"
  }

  expect_failures = [var.bootstrap_format]
}

run "invalid_node_labels" {
  command = plan

  variables {
    node_labels = { team = "platform'; reboot; '" }
  }

  expect_failures = [var.node_labels]
}

run "invalid_autoscaling" {
  command = plan

  variables {
    autoscaling = { enabled = true, min = 5, max = 2 }
  }

  expect_failures = [var.autoscaling]
}

run "invalid_additional_security_group_ids" {
  command = plan

  variables {
    additional_security_group_ids = ["bastion"]
  }

  expect_failures = [var.additional_security_group_ids]
}

run "invalid_additional_tags_count" {
  command = plan

  variables {
    additional_tags = { for i in range(41) : "tag-${i}" => "x" }
  }

  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_length" {
  command = plan

  variables {
    additional_tags = { team = join("", [for i in range(257) : "x"]) }
  }

  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_charset" {
  command = plan

  variables {
    additional_tags = { owner = "x#1" }
  }

  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_reserved" {
  command = plan

  variables {
    additional_tags = { "kubernetes.io/cluster/other" = "owned" }
  }

  expect_failures = [var.additional_tags]
}

run "invalid_autoscaling_target_cpu_percent" {
  command = plan

  variables {
    autoscaling_target_cpu_percent = 0
  }

  expect_failures = [var.autoscaling_target_cpu_percent]
}

run "invalid_external_cluster_exports" {
  command = plan

  variables {
    external_cluster_exports = { schema = "captf.io/aws-cluster/v2" }
  }

  expect_failures = [var.external_cluster_exports]
}

run "invalid_instance_metadata_hop_limit" {
  command = plan

  variables {
    instance_metadata_hop_limit = 1.5
  }

  expect_failures = [var.instance_metadata_hop_limit]
}

run "invalid_instance_type" {
  command = plan

  variables {
    instance_type = "m6i"
  }

  expect_failures = [var.instance_type]
}

run "invalid_machine_image_id" {
  command = plan

  variables {
    machine_image = { id = "ami-XYZ" }
  }

  expect_failures = [var.machine_image]
}

run "invalid_machine_image_name_format" {
  command = plan

  variables {
    machine_image = { name_format = "my-image" }
  }

  expect_failures = [var.machine_image]
}

run "invalid_machine_image_architecture" {
  command = plan

  variables {
    machine_image = { architecture = "aarch64" }
  }

  expect_failures = [var.machine_image]
}

run "invalid_machine_image_owner" {
  command = plan

  variables {
    machine_image = { owner = "1234" }
  }

  expect_failures = [var.machine_image]
}

run "invalid_machine_image_root_device_name" {
  command = plan

  variables {
    machine_image = { root_device_name = "sda1" }
  }

  expect_failures = [var.machine_image]
}

run "invalid_root_volume_kms_key_id" {
  command = plan

  variables {
    root_volume_kms_key_id = "alias/aws/ebs"
  }

  expect_failures = [var.root_volume_kms_key_id]
}

run "invalid_root_volume_size_gib" {
  command = plan

  variables {
    root_volume_size_gib = 20000
  }

  expect_failures = [var.root_volume_size_gib]
}

run "invalid_root_volume_type" {
  command = plan

  variables {
    root_volume_type = "st1"
  }

  expect_failures = [var.root_volume_type]
}

run "invalid_rollout_instance_warmup_seconds" {
  command = plan

  variables {
    rollout_instance_warmup_seconds = -30
  }

  expect_failures = [var.rollout_instance_warmup_seconds]
}
