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

# Unit tests of the machinepool role with a mocked AWS provider: nothing
# reaches AWS. `make unit-test ROLES=machinepool` runs them on Terraform and
# OpenTofu.
#
# Runs share state in file order, so the variants plan first, against no
# state; then happy_path applies, and the later applies change one input at
# a time to show what rolls the instances and what does not.
# machinepool_membership covers members and health, machinepool_validation
# the variable validations.
#
# The pool is team-a/demo-pool-0: sha256 starts 43c6d828.

mock_provider "aws" {
  mock_data "aws_ami_ids" {
    defaults = {
      ids = ["ami-0123456789abcdef0"]
    }
  }
  # No members unless a run overrides the reads.
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
    failure_domains = {
      "us-east-1a" = { subnet_id = "subnet-0aaa0000000000001" }
      "us-east-1b" = { subnet_id = "subnet-0bbb0000000000002" }
      "us-east-1c" = { subnet_id = "subnet-0ccc0000000000003" }
    }
    security_group_ids = { control_plane = ["sg-0c0000000000000c1", "sg-0e0000000000000e1"], worker = ["sg-0e0000000000000e1"] }
    instance_profiles  = { control_plane = "captf-team-a-demo-1960e37c-control-plane", worker = "captf-team-a-demo-1960e37c-worker" }
    api                = null
    bootstrap_bucket   = "captf-bootstrap-20261001000000000000000001"
  }
  captf_tags              = { "captf.io/cluster" = "demo", "captf.io/namespace" = "team-a", "captf.io/kind" = "TerraformMachinePool", "captf.io/name" = "demo-pool-0", "captf.io/managed-by" = "captf", "captf.io/template" = "" }
  machinepool_name        = "demo-pool-0"
  replicas                = 3
  bootstrap_data          = "I2Nsb3VkLWNvbmZpZwpydW5jbWQ6IFtlY2hvIGhlbGxvXQo="
  bootstrap_format        = "cloud-config"
  failure_domains         = []
  cluster_failure_domains = ["us-east-1a", "us-east-1b", "us-east-1c"]
  kubernetes_version      = "v1.34.1"
  node_labels             = {}
  autoscaling             = { enabled = false, min = 0, max = 0 }
  additional_tags         = { team = "platform" }
}

run "autoscaling_disabled" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].min_size == 3 && aws_autoscaling_group.pool_autoscaling_group[0].max_size == 3 && aws_autoscaling_group.pool_autoscaling_group[0].desired_capacity == 3
    error_message = "a fixed-size pool must pin min, max and desired to replicas."
  }
  assert {
    condition     = length(aws_autoscaling_policy.pool_scaling_policy) == 0
    error_message = "a fixed-size pool has no scaling policy."
  }
}

run "autoscaling_enabled" {
  command = plan

  variables {
    autoscaling = { enabled = true, min = 2, max = 5 }
  }

  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].min_size == 2 && aws_autoscaling_group.pool_autoscaling_group[0].max_size == 5 && aws_autoscaling_group.pool_autoscaling_group[0].desired_capacity == 3
    error_message = "an autoscaled pool must take min and max from autoscaling and start at replicas."
  }
  assert {
    condition     = aws_autoscaling_policy.pool_scaling_policy[0].policy_type == "TargetTrackingScaling" && aws_autoscaling_policy.pool_scaling_policy[0].target_tracking_configuration[0].target_value == 60
    error_message = "an autoscaled pool must get a target-tracking policy at autoscaling_target_cpu_percent."
  }
}

run "autoscaling_external" {
  command = plan

  variables {
    autoscaling = { enabled = true, min = 2, max = 5 }
    autoscaler  = "external"
  }

  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].min_size == 2 && aws_autoscaling_group.pool_autoscaling_group[0].max_size == 5 && aws_autoscaling_group.pool_autoscaling_group[0].desired_capacity == 3
    error_message = "an externally autoscaled pool must take min and max from autoscaling and start at replicas."
  }
  assert {
    condition     = length(aws_autoscaling_policy.pool_scaling_policy) == 0
    error_message = "an externally autoscaled pool must not get a scaling policy."
  }
}

run "zero_replicas_healthy" {
  command = plan

  variables {
    replicas = 0
  }

  assert {
    condition     = output.health.state == "running" && output.health.healthy && length(output.health.reasons) == 0
    error_message = "a group scaled to zero is running and healthy."
  }
  assert {
    condition     = length(output.provider_id_list) == 0 && aws_autoscaling_group.pool_autoscaling_group[0].desired_capacity == 0
    error_message = "a group scaled to zero has no members."
  }
}

run "failure_domains_default_to_cluster" {
  command = plan

  assert {
    condition     = jsonencode(terraform_data.inherited_zones.input) == jsonencode(["us-east-1a", "us-east-1b", "us-east-1c"])
    error_message = "with no failure_domains the group must inherit every cluster failure domain (cluster_zone_change_keeps_zones checks the subnets after an apply)."
  }
}

run "failure_domains_fall_back_to_exports" {
  command = plan

  variables {
    cluster_failure_domains = []
  }

  assert {
    condition     = jsonencode(terraform_data.inherited_zones.input) == jsonencode(["us-east-1a", "us-east-1b", "us-east-1c"])
    error_message = "without cluster_failure_domains the group must inherit the zones in exports."
  }
}

run "failure_domains_requested" {
  command = plan

  variables {
    failure_domains = ["us-east-1b"]
  }

  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].vpc_zone_identifier == toset(["subnet-0bbb0000000000002"])
    error_message = "the group must span exactly the requested failure domains."
  }
  assert {
    condition     = length(data.aws_instances.pool_members) == 3
    error_message = "membership must still be read in every cluster zone."
  }
}

run "rejects_unknown_failure_domain" {
  command = plan

  variables {
    failure_domains = ["us-west-2a"]
  }

  expect_failures = [aws_autoscaling_group.pool_autoscaling_group]
}

run "node_labels_rendered" {
  command = plan

  variables {
    node_labels = {
      "cluster.x-k8s.io/cluster-name"  = "demo"
      "node-role.kubernetes.io/worker" = ""
      "node.kubernetes.io/pool"        = "general"
      "team"                           = "platform"
      "topology.kubernetes.io/zone"    = "us-east-1a"
      "example.k8s.io/blocked"         = "yes"
    }
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "captf_node_labels='cluster.x-k8s.io/cluster-name=demo,node.kubernetes.io/pool=general,team=platform,topology.kubernetes.io/zone=us-east-1a'")
    error_message = "the stub must pass the allowed labels, sorted, to --node-labels."
  }
  assert {
    condition     = strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "# captf-node-labels begin") && strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "captf_rke2_file=/etc/rancher/rke2/config.yaml.d/50-captf-node-labels.yaml")
    error_message = "the stub must carry the shared node-labels fragment: the kubelet env files and the RKE2 config.yaml.d drop-in."
  }
  assert {
    condition     = !strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "node-role.kubernetes.io") && !strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "example.k8s.io")
    error_message = "labels the kubelet may not set on itself must be dropped, or it refuses to start."
  }
  assert {
    condition     = jsonencode(output.dropped_node_labels) == jsonencode(["example.k8s.io/blocked", "node-role.kubernetes.io/worker"])
    error_message = "dropped_node_labels must name the labels left out."
  }
}

run "node_labels_unsupported_format" {
  command = plan

  variables {
    bootstrap_format = "ignition"
    bootstrap_data   = "eyJpZ25pdGlvbiI6eyJ2ZXJzaW9uIjoiMy40LjAifX0="
    node_labels      = { team = "platform" }
  }

  expect_failures = [aws_autoscaling_group.pool_autoscaling_group]
}

run "bootstrap_cloud_config" {
  command = plan

  assert {
    condition     = strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "aws s3 cp --only-show-errors --region 'us-east-1' 's3://captf-bootstrap-20261001000000000000000001/pool/demo-pool-0'") && strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "config=/etc/cloud/cloud.cfg.d/99-captf-bootstrap.cfg\n") && startswith(base64decode(aws_launch_template.pool_launch_template[0].user_data), "#cloud-boothook\n#!/bin/sh\n")
    error_message = "the stub must be a boothook that fetches the pool's object and installs it as cloud-init configuration."
  }
  assert {
    condition     = strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "captf_node_labels=''\n")
    error_message = "without labels the fragment gets none, and removes any block an earlier boot wrote."
  }
  assert {
    condition     = nonsensitive(aws_s3_object.bootstrap_object[0].content_base64) == nonsensitive(var.bootstrap_data) && aws_s3_object.bootstrap_object[0].key == "pool/demo-pool-0"
    error_message = "the payload must be staged unchanged under pool/, which workers can read."
  }
}

run "bootstrap_ignition" {
  command = plan

  variables {
    bootstrap_format = "ignition"
    bootstrap_data   = "eyJpZ25pdGlvbiI6eyJ2ZXJzaW9uIjoiMy40LjAifX0="
  }

  assert {
    condition     = jsondecode(base64decode(aws_launch_template.pool_launch_template[0].user_data)) == { ignition = { version = "3.0.0", config = { replace = { source = "s3://captf-bootstrap-20261001000000000000000001/pool/demo-pool-0" } } } }
    error_message = "the Ignition stub must replace itself with the staged config."
  }
}

run "rejects_ignition_gzip" {
  command = plan

  variables {
    bootstrap_format = "ignition"
    bootstrap_data   = "H4sIAAAAAAAC/1NOzskvTdFNzs9Ly0znKirNS85NsVKITk3OyFfISM3JyY/lAgDckH8lIwAAAA=="
  }

  expect_failures = [aws_autoscaling_group.pool_autoscaling_group]
}

run "bootstrap_too_large" {
  command = plan

  variables {
    node_labels = { for i in range(300) : "example.com/label-${i}" => "value-with-some-length-${i}" }
  }

  expect_failures = [aws_autoscaling_group.pool_autoscaling_group]
}

run "externally_managed_without_override" {
  command = plan

  variables {
    captf_cluster_outputs = {}
  }

  expect_failures = [aws_autoscaling_group.pool_autoscaling_group]
}

run "externally_managed_with_override" {
  command = plan

  variables {
    captf_cluster_outputs   = {}
    cluster_failure_domains = []
    external_cluster_exports = {
      schema                = "captf.io/aws-cluster/v1"
      region                = "eu-west-1"
      vpc_id                = "vpc-0fedcba9876543210"
      kubernetes_cluster_id = "legacy"
      failure_domains       = { "eu-west-1a" = { subnet_id = "subnet-0eee0000000000005" } }
      security_group_ids    = { control_plane = ["sg-0c0000000000000c2"], worker = ["sg-0e0000000000000e2"] }
      instance_profiles     = { control_plane = "legacy-cp", worker = "legacy-worker" }
      api                   = null
      bootstrap_bucket      = "legacy-bootstrap"
    }
  }

  assert {
    condition     = jsonencode(terraform_data.inherited_zones.input) == jsonencode(["eu-west-1a"]) && aws_launch_template.pool_launch_template[0].iam_instance_profile[0].name == "legacy-worker"
    error_message = "external_cluster_exports must stand in for the exports of an externally managed cluster."
  }
}

run "rejects_incomplete_exports" {
  command = plan

  variables {
    captf_cluster_outputs = { schema = "captf.io/aws-cluster/v1", region = "us-east-1" }
  }

  expect_failures = [aws_autoscaling_group.pool_autoscaling_group]
}

run "wrong_exports_schema" {
  command = plan

  variables {
    captf_cluster_outputs = { schema = "captf.io/azure-cluster/v1" }
  }

  expect_failures = [var.captf_cluster_outputs]
}

run "rejects_missing_image" {
  command = plan

  override_data {
    target = data.aws_ami_ids.node_images
    values = {
      ids = []
    }
  }

  expect_failures = [aws_launch_template.pool_launch_template]
}

run "spot_and_options" {
  command = plan

  variables {
    spot                          = true
    public_ip                     = true
    additional_security_group_ids = ["sg-0abc000000000000a"]
    machine_image                 = { id = "ami-0aaaaaaaaaaaaaaaa", root_device_name = "/dev/xvda" }
  }

  assert {
    condition     = aws_launch_template.pool_launch_template[0].instance_market_options[0].market_type == "spot" && aws_autoscaling_group.pool_autoscaling_group[0].capacity_rebalance
    error_message = "spot must launch Spot Instances with capacity rebalancing."
  }
  assert {
    condition     = aws_launch_template.pool_launch_template[0].network_interfaces[0].associate_public_ip_address == "true" && aws_launch_template.pool_launch_template[0].network_interfaces[0].security_groups == toset(["sg-0e0000000000000e1", "sg-0abc000000000000a"])
    error_message = "public_ip and the additional security groups must reach the launch template."
  }
  assert {
    condition     = aws_launch_template.pool_launch_template[0].image_id == "ami-0aaaaaaaaaaaaaaaa" && aws_launch_template.pool_launch_template[0].block_device_mappings[0].device_name == "/dev/xvda"
    error_message = "an explicit image and its root device must be used."
  }
}

run "happy_path" {
  assert {
    condition     = output.provider_id == aws_autoscaling_group.pool_autoscaling_group[0].arn
    error_message = "provider_id must be the group's ARN."
  }
  assert {
    condition     = length(output.provider_id_list) == 0 && length(output.instances) == 0
    error_message = "before the first refresh after creation the group reports no members."
  }
  assert {
    condition     = output.replicas == 3
    error_message = "replicas must be the group's desired capacity."
  }
  assert {
    condition     = jsonencode(output.health) == jsonencode({ state = "pending", healthy = false, message = "waiting for the first of 3 instances", reasons = ["NoMembers"] })
    error_message = "a new group without members is pending."
  }
  assert {
    condition     = output.autoscaling_group_name == "captf-team-a-demo-pool-0-43c6d828" && aws_autoscaling_group.pool_autoscaling_group[0].name == "captf-team-a-demo-pool-0-43c6d828"
    error_message = "the group must be named after the pool."
  }
  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].launch_template[0].name == aws_launch_template.pool_launch_template[0].name && aws_autoscaling_group.pool_autoscaling_group[0].launch_template[0].version == "$Latest"
    error_message = "the group must launch the newest version of the launch template."
  }
  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].instance_refresh[0].strategy == "Rolling" && aws_autoscaling_group.pool_autoscaling_group[0].instance_refresh[0].preferences[0].min_healthy_percentage == 100 && aws_autoscaling_group.pool_autoscaling_group[0].instance_refresh[0].preferences[0].max_healthy_percentage == 200
    error_message = "a roll must launch each replacement before terminating an instance."
  }
  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].wait_for_capacity_timeout == "0" && aws_autoscaling_group.pool_autoscaling_group[0].suspended_processes == toset(["AZRebalance"])
    error_message = "the apply must not wait for capacity, and adding a zone must not rebalance running instances away."
  }
  assert {
    condition = alltrue([
      aws_launch_template.pool_launch_template[0].update_default_version,
      aws_launch_template.pool_launch_template[0].image_id == "ami-0123456789abcdef0",
      aws_launch_template.pool_launch_template[0].instance_type == "m6i.large",
      aws_launch_template.pool_launch_template[0].iam_instance_profile[0].name == "captf-team-a-demo-1960e37c-worker",
      aws_launch_template.pool_launch_template[0].metadata_options[0].http_tokens == "required",
      aws_launch_template.pool_launch_template[0].metadata_options[0].http_put_response_hop_limit == 1,
      aws_launch_template.pool_launch_template[0].block_device_mappings[0].device_name == "/dev/sda1",
      aws_launch_template.pool_launch_template[0].block_device_mappings[0].ebs[0].encrypted == "true",
      aws_launch_template.pool_launch_template[0].network_interfaces[0].associate_public_ip_address == "false",
      length(aws_launch_template.pool_launch_template[0].instance_market_options) == 0,
    ])
    error_message = "the launch template must use the worker identity and secure defaults: IMDSv2 with hop limit 1, an encrypted root volume, no public IP, on-demand."
  }
}

run "tags_on_taggable_resources" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for tags in concat(
        [aws_launch_template.pool_launch_template[0].tags],
        [for t in aws_launch_template.pool_launch_template[0].tag_specifications : t.tags],
        [{ for t in aws_autoscaling_group.pool_autoscaling_group[0].tag : t.key => t.value }],
      ) : [for k, v in merge(var.captf_tags, var.additional_tags, { "kubernetes.io/cluster/captf-team-a-demo-1960e37c" = "owned" }) : lookup(tags, k, null) == v]
    ]))
    error_message = "the launch template, everything it launches and the group must carry the captf tags, additional_tags and the cluster ownership tag."
  }
  assert {
    condition     = jsonencode(aws_s3_object.bootstrap_object[0].tags) == jsonencode(var.captf_tags)
    error_message = "the payload object must carry exactly the captf tags (S3 allows 10 per object)."
  }
}

# Each apply below compares with the apply before it: previous_* are
# test-only variables, because OpenTofu resolves run.<name> neither inside an
# assert nor for an apply older than the last one.
run "reapply_is_stable" {
  variables {
    previous_provider_id        = run.happy_path.provider_id
    previous_launch_template_id = run.happy_path.launch_template_id
  }

  assert {
    condition     = output.provider_id == var.previous_provider_id && output.launch_template_id == var.previous_launch_template_id
    error_message = "a second apply must keep the group and the launch template."
  }
}

run "bootstrap_rotation_in_place" {
  variables {
    bootstrap_data              = "I2Nsb3VkLWNvbmZpZwpydW5jbWQ6IFtlY2hvIHJvdGF0ZWRdCg=="
    previous_provider_id        = run.reapply_is_stable.provider_id
    previous_launch_template_id = run.reapply_is_stable.launch_template_id
  }

  assert {
    condition     = output.launch_template_id == var.previous_launch_template_id && output.provider_id == var.previous_provider_id
    error_message = "a bootstrap rotation must not replace the launch template (no roll) or the group."
  }
  assert {
    condition     = nonsensitive(aws_s3_object.bootstrap_object[0].content_base64) == "I2Nsb3VkLWNvbmZpZwpydW5jbWQ6IFtlY2hvIHJvdGF0ZWRdCg=="
    error_message = "a bootstrap rotation must rewrite the staged payload in place."
  }
  assert {
    condition     = !strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "rotated") && !strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), nonsensitive(var.bootstrap_data))
    error_message = "the stub must not carry the payload, raw or base64: a rotation would then make a launch template version."
  }
}

run "node_labels_change_in_place" {
  variables {
    node_labels                 = { team = "data" }
    previous_launch_template_id = run.bootstrap_rotation_in_place.launch_template_id
  }

  assert {
    condition     = output.launch_template_id == var.previous_launch_template_id && strcontains(base64decode(aws_launch_template.pool_launch_template[0].user_data), "--node-labels")
    error_message = "a node label change must update the launch template in place: new members get it, running ones are not replaced."
  }
}

run "instance_type_keeps_template" {
  variables {
    instance_type               = "m6i.xlarge"
    previous_launch_template_id = run.node_labels_change_in_place.launch_template_id
    previous_provider_id        = run.node_labels_change_in_place.provider_id
  }

  assert {
    condition     = output.launch_template_id == var.previous_launch_template_id && output.provider_id == var.previous_provider_id && aws_launch_template.pool_launch_template[0].instance_type == "m6i.xlarge"
    error_message = "an instance type change must update the launch template in place (a new version, no roll) and keep the group."
  }
}

# A mock gives a created resource its override values, and Terraform's mock
# keeps the old ones on an in-place update, so the new ID below proves the
# launch template was replaced, not updated.
run "kubernetes_version_rolls" {
  override_resource {
    target = aws_launch_template.pool_launch_template
    values = {
      id = "lt-0bbbbbbbbbbbbbbbb"
    }
  }

  variables {
    kubernetes_version          = "v1.35.0"
    previous_launch_template_id = run.instance_type_keeps_template.launch_template_id
  }

  assert {
    condition     = output.launch_template_id == "lt-0bbbbbbbbbbbbbbbb" && var.previous_launch_template_id != "lt-0bbbbbbbbbbbbbbbb"
    error_message = "a Kubernetes version change must replace the launch template, which starts an instance refresh."
  }
  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].launch_template[0].name == aws_launch_template.pool_launch_template[0].name
    error_message = "the group must point at the new launch template."
  }
}

run "kubernetes_version_suffix_rolls" {
  override_resource {
    target = aws_launch_template.pool_launch_template
    values = {
      id = "lt-0dddddddddddddddd"
    }
  }

  variables {
    kubernetes_version          = "v1.35.0+rke2r2"
    previous_launch_template_id = run.kubernetes_version_rolls.launch_template_id
  }

  assert {
    condition     = output.launch_template_id == "lt-0dddddddddddddddd" && var.previous_launch_template_id == "lt-0bbbbbbbbbbbbbbbb"
    error_message = "a distribution suffix change (an RKE2 release) is a version change and must roll."
  }
}

run "pinned_image_rolls" {
  override_resource {
    target = aws_launch_template.pool_launch_template
    values = {
      id = "lt-0eeeeeeeeeeeeeeee"
    }
  }

  variables {
    kubernetes_version          = "v1.35.0+rke2r2"
    machine_image               = { id = "ami-0aaaaaaaaaaaaaaaa" }
    previous_launch_template_id = run.kubernetes_version_suffix_rolls.launch_template_id
  }

  assert {
    condition     = output.launch_template_id == "lt-0eeeeeeeeeeeeeeee" && var.previous_launch_template_id == "lt-0dddddddddddddddd"
    error_message = "a change of the pinned image, which carries the kubelet, must roll."
  }
}

# The cluster gains a zone: a pool that inherits the cluster's zones keeps
# the ones it was created with, so no running instance moves.
run "cluster_zone_change_keeps_zones" {
  variables {
    kubernetes_version      = "v1.35.0+rke2r2"
    machine_image           = { id = "ami-0aaaaaaaaaaaaaaaa" }
    cluster_failure_domains = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    captf_cluster_outputs = {
      schema                = "captf.io/aws-cluster/v1"
      region                = "us-east-1"
      vpc_id                = "vpc-0123456789abcdef0"
      kubernetes_cluster_id = "captf-team-a-demo-1960e37c"
      failure_domains = {
        "us-east-1a" = { subnet_id = "subnet-0aaa0000000000001" }
        "us-east-1b" = { subnet_id = "subnet-0bbb0000000000002" }
        "us-east-1c" = { subnet_id = "subnet-0ccc0000000000003" }
        "us-east-1d" = { subnet_id = "subnet-0ddd0000000000004" }
      }
      security_group_ids = { control_plane = ["sg-0c0000000000000c1", "sg-0e0000000000000e1"], worker = ["sg-0e0000000000000e1"] }
      instance_profiles  = { control_plane = "captf-team-a-demo-1960e37c-control-plane", worker = "captf-team-a-demo-1960e37c-worker" }
      api                = null
      bootstrap_bucket   = "captf-bootstrap-20261001000000000000000001"
    }
  }

  assert {
    condition     = aws_autoscaling_group.pool_autoscaling_group[0].vpc_zone_identifier == toset(["subnet-0aaa0000000000001", "subnet-0bbb0000000000002", "subnet-0ccc0000000000003"])
    error_message = "a zone the cluster adds must not reach a pool that inherited the cluster's zones."
  }
  assert {
    condition     = length(data.aws_instances.pool_members) == 4
    error_message = "membership must still be read in every cluster zone."
  }
}
