<h1 align="center">
  <a href="https://captf.io/"><img
    src="https://captf.io/assets/readme/mark.svg"
    width="72" height="72" alt="CAPTF"></a>
  <br>
  terraform-aws-machinepool
</h1>

<p align="center">The CAPTF machine pool module for Amazon Web Services</p>

<p align="center">
  <a href="https://github.com/captf-io/terraform-aws-machinepool/actions/workflows/ci.yml"><img
    src="https://img.shields.io/github/actions/workflow/status/captf-io/terraform-aws-machinepool/ci.yml?branch=main&amp;label=build&amp;labelColor=161B3A&amp;style=flat-square"
    alt="build"></a>
  <a href="https://captf.io/docs/module-author/contract/index.html"><img
    src="https://img.shields.io/static/v1?label=contract&amp;message=v1alpha1&amp;color=A974FF&amp;labelColor=161B3A&amp;style=flat-square"
    alt="contract v1alpha1"></a>
  <a href="https://captf.io/docs/"><img
    src="https://img.shields.io/static/v1?label=docs&amp;message=captf.io&amp;color=5B8CFF&amp;labelColor=161B3A&amp;style=flat-square"
    alt="docs captf.io"></a>
  <a href="https://github.com/captf-io/terraform-aws-machinepool/blob/main/LICENSE.md"><img
    src="https://img.shields.io/static/v1?label=license&amp;message=Apache-2.0&amp;color=FFD84D&amp;labelColor=161B3A&amp;style=flat-square"
    alt="license Apache-2.0"></a>
</p>

> [!NOTE]
> **Pre-release.** CAPTF is `v1alpha1`: its API and its
> [module contract](https://captf.io/docs/module-author/contract/index.html)
> may still change between releases.

The CAPTF AWS machinepool module is the Terraform/OpenTofu root module behind
`TerraformMachinePool`. It is the `machinepool` role for AWS: one Auto Scaling
group per MachinePool. It implements the `v1alpha1`
[machinepool role](https://captf.io/docs/module-author/contract/v1alpha1/machinepool.html).
The images are built from
[aws-modules](https://github.com/captf-io/aws-modules) and published as
`ghcr.io/captf-io/aws-machinepool`; this repository holds the module code
only.

Pool instances are workers; everything cluster-wide comes from the cluster's
exports.

## Using it

CAPTF runs this module from the module image `ghcr.io/captf-io/aws-machinepool`:
set the image on a `TerraformMachinePool`'s `spec.source.image`, and the
controller renders every input. The module is also published to the Terraform
Registry as `captf-io/machinepool/aws` and can be called directly:

```hcl
module "machinepool" {
  source  = "captf-io/machinepool/aws"
  version = "~> 0.1"

  # The contract inputs the controller would render (captf_contract,
  # captf_cluster, captf_object, captf_tags, ...; see Inputs), and any
  # user variables.
}
```

Called directly, the module is a CAPTF root module first:

- it configures its own `provider "aws"` block, so the calling
  module cannot use `count`, `for_each` or `depends_on` on it, and the
  provider takes its credentials from the environment (see Identity
  Secret);
- its providers are pinned to exact versions (`versions.tf`), which the
  calling configuration has to accept;
- you set the `captf_*` inputs yourself.

## What it creates

| Resource | Count | Purpose |
| --- | --- | --- |
| `aws_autoscaling_group.pool_autoscaling_group` | 1 | The group, across the pool's zones; launches `$Latest` of the launch template |
| `aws_launch_template.pool_launch_template` | 1 | What instances launch with: image, type, worker identity and security groups, IMDSv2, encrypted root volume, tags, the user-data stub |
| `aws_autoscaling_policy.pool_scaling_policy` | 0 or 1 | Target-tracking on average CPU while `autoscaling.enabled` |
| `aws_s3_object.bootstrap_object` | 1 | The bootstrap payload, `pool/<machinepool_name>` in the cluster's bucket, rewritten in place on every rotation |
| `terraform_data.kubernetes_version_roll` | 1 | The Kubernetes version and an explicit `machine_image.id`; replacing it replaces the launch template, which rolls the instances |
| `terraform_data.inherited_zones` | 1 | The cluster's zones at the pool's first apply, which a pool without `failure_domains` keeps |

It reads `data.aws_instances.pool_members` (one per cluster zone),
`data.aws_instances.pool_running_members`,
`data.aws_instances.pool_stopped_members` and, without
`machine_image.id`, `data.aws_ami_ids.node_images`.

## Prerequisites

- **A provisioned aws-cluster** (or `external_cluster_exports`).
- **Image.** cloud-init (or Ignition), AWS CLI v2 on the `PATH`, and the
  Kubernetes binaries for the pool's version. `machine_image.root_device_name`
  must be the image's root device (`/dev/sda1` for Ubuntu and the CAPA
  images, `/dev/xvda` for Amazon Linux and Flatcar), or the root volume
  keeps the image's size and encryption.
- **cloud-provider-aws in the workload cluster**, as for machines: a member
  becomes schedulable only once its Node's `providerID` appears in
  `provider_id_list`.
- **Quotas.** One Auto Scaling group, one launch template, the instances'
  vCPUs; a roll needs room for twice the desired capacity.
- **Identity permissions.** `autoscaling:*` on the group (create, update,
  delete, tags, instance refreshes, scaling policies),
  `ec2:CreateLaunchTemplate*`, `ec2:ModifyLaunchTemplate`,
  `ec2:DeleteLaunchTemplate`, and `ec2:RunInstances` plus `iam:PassRole`
  for the worker role (Auto Scaling checks that the caller may launch what
  the template describes),
  `iam:CreateServiceLinkedRole` for `autoscaling.amazonaws.com` once per
  account, and the S3 object permissions: see
  [`examples/identity-policy.json`](https://github.com/captf-io/terraform-aws-machinepool/blob/main/examples/identity-policy.json).

## Inputs

Contract inputs ([machinepool role](https://captf.io/docs/module-author/contract/v1alpha1/machinepool.html#inputs)):

| Input | Used for |
| --- | --- |
| `captf_contract` | Validated to be `v1alpha1` |
| `captf_cluster` | Declared, unused |
| `captf_object` | The namespace in the group's name |
| `captf_cluster_outputs` | Everything cluster-wide; validated to be `captf.io/aws-cluster/v1` or `{}` |
| `captf_tags` | Tags on every taggable resource |
| `machinepool_name` | The group's name, the instances' `Name` tag, the payload's key |
| `replicas` | Desired capacity at creation; min and max while autoscaling is off |
| `bootstrap_data` | The payload, staged as-is; never parsed |
| `bootstrap_format` | `cloud-config` or `ignition`: which stub |
| `failure_domains` | The zones; empty means `cluster_failure_domains` |
| `cluster_failure_domains` | The zones when `failure_domains` is empty (else every zone in exports), recorded at the pool's first apply |
| `kubernetes_version` | Rolls the instances when it changes; the AMI lookup |
| `node_labels` | Rendered into the kubelet's registration (cloud-config only) |
| `autoscaling` | Group min and max, and the scaling policy, when `enabled` |

User variables, set through the TerraformMachinePool's `spec.variables` or
`spec.variablesFrom`:

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `additional_security_group_ids` | `list(string)` | `[]` | Extra security groups for the instances. |
| `additional_tags` | `map(string)` | `{}` | Extra tags for every taggable resource; at most 40, no `aws:`, `captf.io/` or `kubernetes.io/cluster/` keys. |
| `autoscaling_target_cpu_percent` | `number` | `60` | Average CPU the scaling policy holds the group at while autoscaling is enabled. |
| `external_cluster_exports` | `any` | `null` | The exports of an externally managed TerraformCluster, used when `captf_cluster_outputs` is `{}`. |
| `instance_metadata_hop_limit` | `number` | `1` | IMDSv2 hop limit; 2 lets pods without host networking reach the metadata service. |
| `instance_type` | `string` | `"m6i.large"` | EC2 instance type. |
| `machine_image` | `object({id, owner, name_format, architecture, root_device_name})` | `{}`: CAPA images, owner `819546954734`, `capa-ami-ubuntu-24.04-?{semver}-*`, `x86_64`, `/dev/sda1` | `id` pins the AMI; without it the newest AMI matching the format for the Kubernetes version is used. |
| `public_ip` | `bool` | `false` | Give instances a public IPv4 address. |
| `rollout_instance_warmup_seconds` | `number` | `300` | Seconds a refresh waits after each new instance is in service. |
| `root_volume_kms_key_id` | `string` | `null` | KMS key ARN for root volumes; null uses the account's default EBS key. A customer managed key must grant `AWSServiceRoleForAutoScaling`. |
| `root_volume_size_gib` | `number` | `40` | Root volume size. |
| `root_volume_type` | `string` | `"gp3"` | `gp3` or `gp2`. |
| `spot` | `bool` | `false` | Launch Spot Instances, with capacity rebalancing. |
| `ssh_key_name` | `string` | `null` | EC2 key pair; no rule admits SSH either way. |

## Outputs

| Output | Value |
| --- | --- |
| `provider_id` | The Auto Scaling group's ARN |
| `provider_id_list` | `aws:///<zone>/<instance-id>` of every `pending`, `running`, `stopping` or `stopped` instance tagged `aws:autoscaling:groupName = <group>`, sorted |
| `replicas` | The group's desired capacity as last observed |
| `instances` | Per member: `provider_id`, `instance_id`, `addresses` (`InternalIP`), `failure_domain`, `state` |
| `health` | See Health |

Non-contract outputs (`outputs_extra.tf`): `autoscaling_group_name`,
`dropped_node_labels` (the labels left out of the kubelet's registration)
and `launch_template_id`.

## Exports

The machinepool role exports nothing. It reads the cluster's
(`captf.io/aws-cluster/v1`, see [the cluster README](https://github.com/captf-io/terraform-aws-cluster#exports)):
every field but `api`.

## Identity Secret

The provider sets only the region, from the cluster's exports; credentials
come from the identity Secret as for the cluster role
([cluster README](https://github.com/captf-io/terraform-aws-cluster#identity-secret)).

## Lifecycle

| Change | Launch template | Running instances |
| --- | --- | --- |
| `bootstrap_data` (the kubeadm token, about every 7.5 minutes) | unchanged: only the S3 object is rewritten | kept |
| `node_labels`, `instance_type`, `machine_image`, `spot`, root volume, security groups | new version under `$Latest` | kept; new instances get it |
| `kubernetes_version`, distribution suffix included (`+rke2r1` to `+rke2r2`) | replaced (create before destroy) | replaced by a rolling instance refresh, each new instance launched before an old one is terminated |
| an explicit `machine_image.id` | replaced | replaced by a rolling refresh, as for a version (see Exceptions) |
| `replicas` (autoscaling off) | unchanged | the group grows or shrinks |
| a zone the cluster adds or removes, for a pool without `failure_domains` | unchanged | kept: the pool's zones are the cluster's at its first apply (`terraform_data.inherited_zones`) |
| a zone added to `failure_domains` | unchanged | kept: `AZRebalance` is suspended, so new instances go to the new zone over time |
| a zone removed from `failure_domains` | unchanged | the instances in it are replaced in the other zones, undrained (see Exceptions) |

A refresh never starts for a new version of the same template under
`$Latest`; only the new template of a version or pinned-image change starts
one. Nothing else replaces running instances: other changes reach the group
as instances are replaced by scale-in, Spot rebalancing or the next roll.

## Bootstrap

As for [machines](https://github.com/captf-io/terraform-aws-machine#bootstrap), from a boothook
that downloads the payload from S3 and installs it in
`/etc/cloud/cloud.cfg.d`, so a token rotation never touches the launch
template (each change of user data would cost one of the 10,000 versions a
launch template can have, used up in about 52 days of rotations). For
`cloud-config`, the boothook also registers `node_labels` before the kubelet
starts: it appends `--node-labels` to `KUBELET_EXTRA_ARGS` in
`/etc/default/kubelet` (`/etc/sysconfig/kubelet` on RHEL-like systems) and
writes `/etc/rancher/rke2/config.yaml.d/50-captf-node-labels.yaml` with
`node-label+` for RKE2. Labels in the `kubernetes.io` and `k8s.io`
namespaces that a kubelet may not set on itself (`node-role.kubernetes.io/*`
among them) are dropped: the kubelet would refuse to start with them.

## Tags

The group carries `captf_tags`, `additional_tags` and
`kubernetes.io/cluster/<id> = owned` (not propagated: instances get theirs
from the launch template). The launch template carries the same, and tags
what it launches (instances, volumes, network interfaces) with them plus
`Name = <machinepool_name>` on instances and volumes. The S3 object carries
`captf_tags` only (S3 allows 10 tags per object). Scaling policies cannot
be tagged.

## Health

| Condition | `state` | `healthy` | `reasons` |
| --- | --- | --- | --- |
| The group was deleted out of band | `terminated` | `false` | `GroupNotFound` |
| Desired capacity 0 | `running` | `true` | `[]` |
| No member yet | `pending` | `false` | `NoMembers` |
| A member is `stopping` or `stopped` | `stopped` | `false` | `InstanceStopped:<instance-id>` per member |
| Every member running, as many as desired | `running` | `true` | `[]` |
| Otherwise (members still `pending`, or fewer or more than desired) | `running` | `false` | `InstancePending:<instance-id>` per member, `ScalingInProgress` |

Member states: `pending` → `pending`, `running` → `running`, `stopping` and
`stopped` → `stopped`. A pending member does not make the pool `pending`:
the contract keeps that for a group with no members, and the controller
refreshes every 30 seconds anyway while the member count differs from the
desired capacity.

## Limitations

- **No drain.** Scale-in, a roll and Spot rebalancing terminate instances
  without draining their nodes (the contract's pools have no Machines to
  drain). Run a termination handler such as aws-node-termination-handler
  in queue mode with an Auto Scaling lifecycle hook if workloads need it.
- **CPU target tracking is a proxy**: pods waiting for capacity do not raise
  CPU. The Kubernetes Cluster Autoscaler cannot drive these pools (it needs
  MachinePool Machines).
- **Node labels need cloud-config.** With Ignition, labels are refused
  (precondition); after the kubernetes.io filter, nothing else is.
- **Membership spans the cluster's zones**, read per zone every refresh
  (one `DescribeInstances` per zone, plus two for member states).
- **Removing a zone** replaces the instances in it without draining them.
- **Labels change for new members only**: running members keep the labels
  they registered with until they are replaced.
- **The payload stays in Terraform state** (`content_base64` of the S3
  object), as every input does in CAPTF's state and inputs Secrets.

## Exceptions

- A change of an explicit `machine_image.id` rolls the instances, besides a
  Kubernetes version change: the pinned image carries the kubelet, and
  with ClusterClass it can render in a later apply than the version
  (DESIGN.md decision 6).
- Removing a zone from `failure_domains` replaces the instances in it:
  the group cannot keep instances in a zone it no longer spans. Zones a
  pool inherits from the cluster never change.

`tfcapi-lint module --strict` passes without allowed warnings.

## Examples

[`examples/cluster-kubeadm.yaml`](https://github.com/captf-io/terraform-aws-machinepool/blob/main/examples/cluster-kubeadm.yaml) adds an
autoscaled pool:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
kind: TerraformMachinePool
metadata:
  name: demo-pool-0
  labels:
    cluster.x-k8s.io/cluster-name: demo
spec:
  source:
    image: ghcr.io/captf-io/aws-machinepool:v0.1.0-opentofu
  variables:
    instance_type: m6i.large
```

## Developing

The host needs `make`, `podman` (or `docker` with `ENGINE=docker`), `jq` and
Go; every other tool runs in a digest-pinned container. `make verify` is the
gate. `tfcapi-lint` is built from `../cluster-api-provider-terraform`
(`PROVIDER_DIR`); without that checkout the target skips.

| Target | What it does |
| --- | --- |
| `make fmt` | Format the module with `terraform fmt` and `tofu fmt`, in place. |
| `make fmt-check` | Fail on any file either formatter would change. |
| `make validate` | `init` and `validate` on both runtimes and on their floors (Terraform 1.5.7, OpenTofu 1.6.3). |
| `make unit-test` | `terraform test` and `tofu test` with mocked providers. |
| `make tflint` | `tflint` with the terraform ruleset (preset all) and the cloud ruleset. |
| `make tfcapi-lint` | `tfcapi-lint module --strict`. |
| `make scan` | `trivy config` over the repository; ignores live in `.trivyignore.yaml`. |
| `make check-conventions` | `hack/check-layout.sh` and `hack/check-tags.sh` (CONVENTIONS.md). |
| `make shellcheck` | `shellcheck` over `hack/` and every shell template, rendered with placeholders. |
| `make check-headers` | Fail on any source file without the Apache-2.0 license header. |
| `make fix-headers` | Add the license header to every source file missing it. |
| `make verify` | Everything above, in parallel groups. |
| `make clean` | Remove `build/`. |

`RUNTIMES=opentofu` limits a run to one runtime.

<br>
<p align="center">
  <img
    src="https://captf.io/assets/readme/divider.svg"
    width="100%" height="4" alt="">
</p>
<p align="center">
  <a href="https://captf.io/"><img
    src="https://captf.io/assets/readme/mark.svg"
    width="40" height="40" alt="CAPTF"></a>
  <br>
  <a href="https://captf.io/docs/"
    ><b>Documentation</b></a> ·
  <a href="https://captf.io/docs/getting-started/quick-start.html"
    ><b>Quick start</b></a> ·
  <a href="https://github.com/captf-io/.github/blob/main/CONTRIBUTING.md"
    ><b>Contributing</b></a> ·
  <a href="https://github.com/captf-io/.github/blob/main/SECURITY.md"
    ><b>Security</b></a>
  <br>
  <sub>Built for
    <a href="https://cluster-api.sigs.k8s.io/">Cluster API</a>.
    <a href="https://github.com/captf-io/terraform-aws-machinepool/blob/main/LICENSE.md"
    >Apache 2.0</a>.</sub>
</p>
