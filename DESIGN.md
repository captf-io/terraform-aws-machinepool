# Design: terraform-aws-machinepool

Why this module looks the way it does. Each decision names the evidence it
rests on; anything not yet checked against a real AWS account is listed
under "Unverified" and must be confirmed on the first reviewed apply.

Pins: `hashicorp/aws` 6.67.0. Runtimes: Terraform >= 1.5, OpenTofu >= 1.6.
Conventions: [CONVENTIONS.md](CONVENTIONS.md). Contract:
<https://captf.io/docs/module-author/contract/v1alpha1/>.

Provider facts below were checked against `providers schema -json` of the
pinned provider and its source at the `v6.67.0` tag; file names refer to
`internal/service/<service>/` in `hashicorp/terraform-provider-aws`.

The AWS modules share one design. Decision numbers are the same in every
repository ([cluster](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md), [machine](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md), [machinepool](https://github.com/captf-io/terraform-aws-machinepool/blob/main/DESIGN.md)), so a reference such as "decision 1" means the same
decision everywhere; a number missing here belongs to another role.

## Scope

- This repository is the `machinepool` role: one Auto Scaling group for each MachinePool; pool instances are workers.
- Everything cluster-wide comes from the cluster's exports. The cluster role is in
  [terraform-aws-cluster](https://github.com/captf-io/terraform-aws-cluster), the machine role in
  [terraform-aws-machine](https://github.com/captf-io/terraform-aws-machine).

## Decisions

### 1. Bootstrap payloads are staged in S3

The contract suggests `aws_launch_template.user_data = var.bootstrap_data`
for pools. Pool bootstrap data rotates about every 7.5 minutes (kubeadm
token refresh), and every user-data change creates a launch template
version. AWS allows 10,000 versions per launch template (EC2 User Guide,
"Restrictions for launch templates"): about 52 days of rotations, after
which every pool apply fails. Terraform has no resource that prunes
versions. Secrets Manager (100 unlabelled versions, none removed within 24
hours) and SSM Parameter Store (4 KB / 8 KB values) do not fit either.

So the cluster creates one S3 bucket per cluster. The machine and pool
roles write the payload to an object (`aws_s3_object`, `content_base64 =
var.bootstrap_data`, which the provider decodes to raw bytes, so gzip is
safe) and give the instance a small user-data stub that fetches it:

- cloud-config: a `#cloud-boothook` script that copies `s3://<bucket>/<key>`
  with the AWS CLI (60 attempts, 5 s apart; once per instance, guarded by
  the file it writes, since boothooks run on every boot), gunzips when the
  bytes start with `1f 8b`, refuses anything that is not cloud-config
  (`#cloud-config`, or `## template: jinja` then `#cloud-config`, as CABPK
  writes), and installs it atomically (`umask 077`, mode 0600, temporary
  file and `mv`) as `/etc/cloud/cloud.cfg.d/99-captf-bootstrap.cfg`. That
  works on stock cloud-init: after the boothooks (`consume_data`,
  `cmd/main.py` 596-608), `stages.py` 828 `_reset()` drops the cached
  configuration and the module stages read it again, `cloud.cfg.d`
  included (`stages.py` 276-311, `util.read_conf_with_confd`), before the
  init, config and final modules run; a `cloud.cfg.d` file that starts
  with `## template: jinja` is rendered (`util.py` 312-350). The payload
  then merges as system configuration: dictionaries merge, lists replace
  (a later file's `runcmd` wins), and `merge_how` is ignored.

  CAPA's pattern, a boothook plus a `text/x-include-url` part naming the
  fetched file, does not work on stock cloud-init: `init.update()`
  resolves includes (`cmd/main.py` 589, `stages.py` 570,
  `sources/__init__.py` 648-650, `user_data.py` 157-159 `_do_include`)
  before boothooks run, and the missing file aborts init because
  `features.ERROR_ON_USER_DATA_FAILURE` is true (`features.py` 21). CAPA
  works only through image-builder patches (CAPA #2757, #4745, #5115).
- Ignition: `{"ignition":{"version":"3.0.0","config":{"replace":{"source":"s3://<bucket>/<key>"}}}}`;
  Ignition fetches `s3://` with the instance role (spec 3.0.0+). Ignition
  cannot fetch compressed S3 objects, so Ignition plus gzip fails a
  precondition.

The pool object is updated in place on every rotation: no launch template
version, no instance refresh. This also meets the control-plane checklist
rule to keep key material out of readable instance metadata. The machine's
instance `depends_on` its object, so the first fetch finds it; the object
is planned only when the exports name a bucket, so incomplete exports are
reported by the instance's precondition rather than by a null `bucket`.

The bucket, its policy and the read access by key prefix are the cluster
role's: see decision 1 of the [terraform-aws-cluster DESIGN.md](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md).

Pools are S3-only; the machine role also offers `bootstrap_delivery = "inline"` ([terraform-aws-machine DESIGN.md](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md)).

Requirement: the AMI has cloud-init and AWS CLI v2. image-builder installs
the CLI on non-Amazon distributions (`roles/providers/tasks/aws.yml`).

### 2. API load balancer

This role does not own this decision: see the [terraform-aws-cluster DESIGN.md](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md).

### 3. Security groups

This role does not own this decision: see the [terraform-aws-cluster DESIGN.md](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md).

### 4. Node identities

This role does not own this decision: see the [terraform-aws-cluster DESIGN.md](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md).

### 5. Machine

This role does not own this decision: see the [terraform-aws-machine DESIGN.md](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md).

### 6. Machine pool

- Launch template with `update_default_version = true`; the ASG uses
  `version = "$Latest"`. The provider starts an instance refresh when the
  ASG's `launch_template` block changes (`autoscaling/group.go`,
  `shouldRefreshInstances`), and "a refresh will not start when version =
  $Latest" for a new version of the same template (provider docs).
- Rolls happen only by replacing the launch template, on a Kubernetes
  version change: `replace_triggered_by = [terraform_data.kubernetes_version_roll]`,
  whose `triggers_replace` is `kubernetes_version` verbatim (an RKE2 bump
  from `+rke2r1` to `+rke2r2` is a version change; stripping is for image
  lookups and comparisons only) and an explicit `machine_image.id`: a
  pinned image carries the kubelet, and with ClusterClass the version and
  the image render in separate applies, so an image change after the
  version must still roll or the upgrade never completes. A looked-up image
  does not count (a re-published CAPA image would roll every pool).
  `create_before_destroy` with `name_prefix`. The design pass's
  `rollout_generation` (a manual roll) was dropped: the contract asks for
  no other trigger that replaces instances. The ASG references the
  template by name, new for every replacement, so its `launch_template`
  block changes, which starts a Rolling refresh (min healthy 100 %, max
  healthy 200 %: launch-before-terminate). A refresh already running is
  cancelled and restarted by the provider (`startInstanceRefresh`).
- Zones: a pool without `failure_domains` keeps the cluster's zones as of
  its first apply (`terraform_data.inherited_zones`, `ignore_changes`), so
  a zone the cluster adds or drops never moves running instances
  (CONVENTIONS.md section 13); zones the cluster no longer has are left
  out. `suspended_processes = ["AZRebalance"]`: a zone added to
  `failure_domains` would otherwise make Auto Scaling terminate running
  instances, undrained, to even out the zones. Removing one still
  replaces the instances in it (README "Exceptions").
- `triggers = ["tag"]` was rejected: it would roll on any `captf_tags`
  change too.
- Other launch template changes (labels, instance type, spot, image) create
  versions under `$Latest`: new instances get them, existing ones are not
  replaced; they spread as instances are replaced.
- `min_size`, `max_size` and `desired_capacity` are written inline against
  `var.autoscaling` (tfcapi-lint only recognises a scaling group that
  references `var.autoscaling` itself), with
  `ignore_changes = [desired_capacity]`. Autoscaling off pins
  min = max = replicas, and `UpdateAutoScalingGroup` moves the desired
  capacity into the new bounds; on, a target-tracking CPU policy.
- `wait_for_capacity_timeout = "0"`: membership is the refresh loop's job,
  and a create that timed out waiting for capacity would taint the group,
  so the next apply would replace it.
- The launch template's root `block_device_mappings` needs the image's root
  device name, which `aws_ami_ids` does not return and `aws_ami` would fail
  to read once an image is deregistered; it is
  `machine_image.root_device_name` (default `/dev/sda1`, Ubuntu and CAPA).
- Membership: `data.aws_instances` per cluster zone, filtered by
  `tag:aws:autoscaling:groupName` (a literal name, so the read happens at
  plan time) and the states pending, running, stopping and stopped; plus
  two group-wide reads, running and stopping/stopped, for each member's
  state (anything else is pending). `provider_id_list` is sorted and
  de-duplicated. `replicas` is the ASG's `desired_capacity`.
- `node_labels` are rendered by the stub before kubelet starts
  (CONVENTIONS.md section 13), minus the `kubernetes.io`/`k8s.io` labels
  the kubelet refuses (`IsKubeletLabel`, k8s.io/kubelet
  `pkg/apis/well_known_labels.go`).

### 7. provider_id, health

- `aws:///<availability-zone>/<instance-id>`: cloud-provider-aws v1.36.1
  `InstanceID()` returns `/<AZ>/<instance-id>` and `getProviderID` prefixes
  `aws://`.
- The CCM finds unregistered nodes by private DNS name, so the node name
  must be the instance's private DNS name (the examples set kubeadm's
  `nodeRegistration.name` to `{{ ds.meta_data.local_hostname }}`, as CAPA's
  templates do).
- Pool health, in CONVENTIONS.md section 10's order: the group gone →
  `terminated` (`GroupNotFound`); desired 0 → running/healthy; no member →
  pending (`NoMembers`); a member stopping or stopped → `stopped`
  (`InstanceStopped:<id>`); otherwise running, healthy only when every
  member runs and the count equals the desired capacity, with
  `InstancePending:<id>` per starting member and `ScalingInProgress` on a
  count mismatch. A starting member never makes the pool pending.

### 8. Tags

- `local.tags` on every taggable resource, explicitly. No provider
  `default_tags`: they do not reach ASG-launched instances, and mocks cannot
  assert them.
- Instances also carry `Name` and `kubernetes.io/cluster/<id> = owned`
  (the CCM discovers the cluster ID from its own instance's tags).
- Limits: 50 tags, keys 128, values 256, `aws:` reserved, empty values
  allowed. S3 objects take at most 10 tags, so objects carry only the
  captf tags (`hack/tags.json`).

### 9. Credentials

The provider block sets only `region` (cluster: `var.region`, null means
`AWS_REGION`; machine and pool: the cluster's exported region). Everything
else comes from the SDK chain:

- static keys: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`;
- assume role: `AWS_CONFIG_FILE=/var/run/captf/credentials/config`,
  `AWS_SHARED_CREDENTIALS_FILE=/var/run/captf/credentials/credentials`,
  `AWS_PROFILE`, with `config` and `credentials` file keys in the Secret.

`HOME` is `/captf/work`, so `~/.aws` never exists. IRSA needs a projected
token the CAPTF Job does not mount.

### 10. Network input

The cluster role reads the VPC and subnets (decision 10 of the
[terraform-aws-cluster DESIGN.md](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md)); the pool takes the zone to subnet map from the exports.

Resources whose disappearance health must report (the bucket, the
instance, the group) use `count = 1`: once a refresh drops a bare
resource from state its references read as unknown, which `try()` cannot
catch, so outputs go null; an empty tuple fails the index and `try()` falls
back (checked with local_file on Terraform 1.16.4 and OpenTofu 1.12.6). A list of subnets with
zones read from AWS was rejected: one subnet per zone and one VPC then need
cross-instance checks that OpenTofu's mocks cannot exercise (overrides
cannot target one `for_each` instance).

## Cluster exports consumed

Schema `captf.io/aws-cluster/v1`, produced by the cluster role; the full
shape is under "Exports" in the [terraform-aws-cluster DESIGN.md](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md).
It reads `schema`, `region`, `kubernetes_cluster_id`, `failure_domains`,
`security_group_ids.worker`, `instance_profiles.worker` and `bootstrap_bucket`;
`api` is not needed, since pool instances register in no target group.

Machines and pools normalize the exports into one shape with `try()` per
field, and select them from `captf_cluster_outputs` or
`external_cluster_exports` with a tuple index: a conditional refuses two
object values of different shapes.

## Unverified

**1.** The `cloud.cfg.d` merge semantics on a real boot: the payload merged
as system configuration (lists replace, so an image's own
`cloud.cfg.d` `runcmd` or `write_files` would be overridden), its Jinja
rendered there, and no image-builder patch interfering; also AWS CLI v2
on the AMIs in use.

**2.** `--node-labels` appended to `KUBELET_EXTRA_ARGS` merges with user
`kubeletExtraArgs` (the kubelet merges repeated map flags);
`/etc/default/kubelet` is the file the kubeadm drop-in reads on the
images in use; RKE2 `config.yaml.d` `node-label+` append semantics.

**3.** Instance refresh rounding for very small groups at 100/200 %.

**4.** Concerns another role: see the DESIGN.md of [terraform-aws-machine](https://github.com/captf-io/terraform-aws-machine/blob/main/DESIGN.md).

**5.** Concerns another role: see the DESIGN.md of [terraform-aws-cluster](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md).

**6.** Concerns another role: see the DESIGN.md of [terraform-aws-cluster](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md).

**7.** Concerns another role: see the DESIGN.md of [terraform-aws-cluster](https://github.com/captf-io/terraform-aws-cluster/blob/main/DESIGN.md).

**8.** `examples/identity-policy.json` is complete for create, update and
destroy of all three roles.

**9.** An Ignition 3.0.0 stub replacing itself with a newer-spec config.

**10.** An Auto Scaling group launching Spot through the launch template's
 `instance_market_options` (CAPA does the same).

## Rejected alternatives

- Bootstrap in launch template user data (version quota, above).
- A boothook plus an `x-include-url` part naming the fetched file (CAPA's
  pattern): stock cloud-init resolves the include first and aborts
  (decision 1).
- `triggers = ["tag"]` for rolls (rolls on unrelated tag changes).
- Provider `default_tags` (does not reach ASG launches; untestable).
- `data.aws_ami` for the lookup (fails a refresh once the image is
  deregistered).
- Per-state membership reads per zone: four times the calls, and untestable
  on OpenTofu (decision 10's mock limit).
