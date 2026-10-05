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

# Members, provider_id_list, instances and health from the membership reads.
# The cluster has one zone here: the reads are overridden whole, and a mock
# cannot give each zone's read its own answer on both runtimes. The group is
# created by the first run; every later run re-reads the members, as a
# membership refresh does.

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
  replicas                = 3
  bootstrap_data          = "I2Nsb3VkLWNvbmZpZwpydW5jbWQ6IFtlY2hvIGhlbGxvXQo="
  bootstrap_format        = "cloud-config"
  failure_domains         = []
  cluster_failure_domains = ["us-east-1a"]
  kubernetes_version      = "v1.34.1"
  node_labels             = {}
  autoscaling             = { enabled = false, min = 0, max = 0 }
}

run "no_members_pending" {
  assert {
    condition     = output.health.state == "pending" && jsonencode(output.health.reasons) == jsonencode(["NoMembers"])
    error_message = "a group without members is pending."
  }
}

run "membership_excludes_terminated" {
  command = plan

  assert {
    condition     = data.aws_instances.pool_members["us-east-1a"].instance_state_names == toset(["pending", "running", "stopping", "stopped"])
    error_message = "membership must count every state but shutting-down and terminated."
  }
  assert {
    condition     = jsonencode([for f in data.aws_instances.pool_members["us-east-1a"].filter : f.values if f.name == "tag:aws:autoscaling:groupName"]) == jsonencode([["captf-team-a-demo-pool-0-43c6d828"]]) && jsonencode([for f in data.aws_instances.pool_running_members.filter : f.values if f.name == "tag:aws:autoscaling:groupName"]) == jsonencode([["captf-team-a-demo-pool-0-43c6d828"]])
    error_message = "membership must be read by the tag Auto Scaling puts on the group's instances, with the group's name."
  }
}

run "membership_reports_every_member" {
  override_data {
    target = data.aws_instances.pool_members
    values = {
      ids         = ["i-0ccc0000000000003", "i-0aaa0000000000001", "i-0bbb0000000000002"]
      private_ips = ["10.0.1.13", "10.0.1.11", "10.0.1.12"]
    }
  }
  override_data {
    target = data.aws_instances.pool_running_members
    values = {
      ids = ["i-0aaa0000000000001", "i-0bbb0000000000002"]
    }
  }

  assert {
    condition = jsonencode(output.provider_id_list) == jsonencode([
      "aws:///us-east-1a/i-0aaa0000000000001",
      "aws:///us-east-1a/i-0bbb0000000000002",
      "aws:///us-east-1a/i-0ccc0000000000003",
    ])
    error_message = "provider_id_list must hold every member, pending ones included, sorted."
  }
  assert {
    condition = jsonencode(output.instances) == jsonencode([
      { provider_id = "aws:///us-east-1a/i-0aaa0000000000001", instance_id = "i-0aaa0000000000001", addresses = [{ type = "InternalIP", address = "10.0.1.11" }], failure_domain = "us-east-1a", state = "running" },
      { provider_id = "aws:///us-east-1a/i-0bbb0000000000002", instance_id = "i-0bbb0000000000002", addresses = [{ type = "InternalIP", address = "10.0.1.12" }], failure_domain = "us-east-1a", state = "running" },
      { provider_id = "aws:///us-east-1a/i-0ccc0000000000003", instance_id = "i-0ccc0000000000003", addresses = [{ type = "InternalIP", address = "10.0.1.13" }], failure_domain = "us-east-1a", state = "pending" },
    ])
    error_message = "instances must report each member's IDs, address, zone and state."
  }
  assert {
    condition     = jsonencode(output.health) == jsonencode({ state = "running", healthy = false, message = "2 of 3 instances running", reasons = ["InstancePending:i-0ccc0000000000003"] })
    error_message = "a pending member keeps the pool running but unhealthy, naming the member."
  }
  assert {
    condition     = output.replicas == 3
    error_message = "replicas must be the desired capacity, not the running count."
  }
}

run "all_members_running_healthy" {
  override_data {
    target = data.aws_instances.pool_members
    values = {
      ids         = ["i-0aaa0000000000001", "i-0bbb0000000000002", "i-0ccc0000000000003"]
      private_ips = ["10.0.1.11", "10.0.1.12", "10.0.1.13"]
    }
  }
  override_data {
    target = data.aws_instances.pool_running_members
    values = {
      ids = ["i-0aaa0000000000001", "i-0bbb0000000000002", "i-0ccc0000000000003"]
    }
  }

  assert {
    condition     = jsonencode(output.health) == jsonencode({ state = "running", healthy = true, message = "3 of 3 instances running", reasons = [] })
    error_message = "every member running at the desired capacity is healthy."
  }
}

run "stopped_member_is_worst_state" {
  override_data {
    target = data.aws_instances.pool_members
    values = {
      ids         = ["i-0aaa0000000000001", "i-0bbb0000000000002", "i-0ccc0000000000003"]
      private_ips = ["10.0.1.11", "10.0.1.12", "10.0.1.13"]
    }
  }
  override_data {
    target = data.aws_instances.pool_running_members
    values = {
      ids = ["i-0aaa0000000000001", "i-0ccc0000000000003"]
    }
  }
  override_data {
    target = data.aws_instances.pool_stopped_members
    values = {
      ids = ["i-0bbb0000000000002"]
    }
  }

  assert {
    condition     = output.health.state == "stopped" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["InstanceStopped:i-0bbb0000000000002"])
    error_message = "a stopped member makes the pool stopped, naming the member."
  }
  assert {
    condition     = length(output.provider_id_list) == 3
    error_message = "a stopped member is still a member."
  }
}

run "capacity_mismatch_is_unhealthy" {
  override_data {
    target = data.aws_instances.pool_members
    values = {
      ids         = ["i-0aaa0000000000001", "i-0bbb0000000000002"]
      private_ips = ["10.0.1.11"]
    }
  }
  override_data {
    target = data.aws_instances.pool_running_members
    values = {
      ids = ["i-0aaa0000000000001", "i-0bbb0000000000002"]
    }
  }

  assert {
    condition     = output.health.state == "running" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["ScalingInProgress"])
    error_message = "fewer members than the desired capacity is running but unhealthy."
  }
  assert {
    condition     = alltrue([for i in output.instances : length(i.addresses) == 0])
    error_message = "addresses must be left out when the private IPs do not line up with the IDs."
  }
}
