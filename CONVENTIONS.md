# Module conventions

The rules every CAPTF module repository follows: the `terraform-<provider>-<role>`
repositories, one per cloud and role (`terraform-aws-cluster`,
`terraform-google-machine`, `terraform-azure-machinepool`, and so on). Each
holds exactly one CAPTF root module. This file is identical across all of
them; a change here is a change in all of them.

MUST and MUST NOT are enforced by `make verify` where a tool can check them
and by review where it cannot. A deliberate deviation is listed, with its
reason, under "Exceptions" in the repository's README.

The module contract itself lives at
<https://captf.io/docs/module-author/contract/v1alpha1/>. These conventions
add to it; where they seem to disagree, the contract wins and this file is
wrong.

## 1. Repository layout

```text
terraform-<provider>-<role>/
  README.md                 what the module creates, how to develop it
  CONVENTIONS.md            this file
  DESIGN.md                 why the module looks the way it does
  LICENSE.md                Apache-2.0
  Makefile                  every check; `make help`
  .gitignore .licenserc.yaml .tflint.hcl .trivyignore.yaml
  .github/workflows/ci.yml  .github/dependabot.yml
  hack/                     check-layout.sh, check-tags.sh, tags.json,
                            check-shell.sh, tf-run.sh (one runtime action,
                            in a pinned container), testdata/
  examples/                 README.md, identity Secret and manifests that
                            use the module image
  *.tf  templates/*.tftpl  tests/*.tftest.hcl
                            the root module, at the repository root
```

The module is for one role (`cluster`, `machine` or `machinepool`), named
by the repository. The repository also carries the community files
(`CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODEOWNERS`, the
pull request template).

The repository root never contains `.terraform/` or `.terraform.lock.hcl`;
both are gitignored (section 5).

These files are byte-identical across all `terraform-*` repositories and
stay so: `CONVENTIONS.md`, `hack/tf-run.sh`, `hack/check-layout.sh`,
`hack/check-shell.sh`, `hack/check-tags.sh`, `hack/testdata/`,
`.gitignore`, `.licenserc.yaml`, `.github/workflows/ci.yml` and
`.github/dependabot.yml`. No tooling enforces this: apply a change to every
repository, then `diff` against `terraform-aws-cluster`. The `Makefile`
differs only in its per-repository values: the header comment,
`CLOUD`, `ROLE` and `TFCAPI_LINT_ALLOW`.

## 2. Files in the module

These files may hold more than one block, and only the blocks named:

| File | Holds |
| --- | --- |
| `versions.tf` | one `terraform {}` block: `required_version`, `required_providers` |
| `providers.tf` | every `provider` block, aliases included |
| `variables_contract.tf` | the role's contract inputs, in contract order, with the contract's types |
| `variables.tf` | user variables, alphabetical |
| `outputs.tf` | the role's contract outputs, in contract order |
| `outputs_extra.tf` | non-contract outputs, alphabetical |
| `locals_<topic>.tf` | `locals` blocks for one topic: `names`, `tags`, `health`, `exports`, `cluster`, `placement`, `bootstrap`, `kubernetes_version`, `api`, `identity`, `network`, `security_rules`, `image`, `membership`, `autoscaling`, or a cloud-specific topic |

Every other `.tf` file holds exactly ONE `resource` or `data` block:

- The file stem is the block's local name. Data sources prefix `data_`:
  `resource "aws_lb" "api_load_balancer"` lives in `api_load_balancer.tf`;
  `data "aws_ami" "node_image"` lives in `data_node_image.tf`.
- Local names are snake_case `<purpose>_<kind>`, where `<kind>` names the
  cloud object: `api_load_balancer`, `api_listeners`, `node_instance`,
  `control_plane_security_group`, `node_ingress_rules`,
  `pool_launch_template`. A `for_each` block takes a plural name. Never
  `this`, `main`, `default`, `example` or `self`.
- Two names are fixed in every repository: `terraform_data.api_endpoint_guard`
  (section 12) and `terraform_data.kubernetes_version_roll` (section 13).
- One block may use `for_each` over a map of many similar objects (all the
  ingress rules of one security group); that is still one block.

Not allowed in the module: `main.tf`, `.tofu` and `.tf.json` files,
`module` calls (modules are flat), `check` blocks (use preconditions),
`backend` and `cloud` blocks, `moved`/`removed`/`import` blocks, and
provisioners.

User-data templates live in `templates/<name>.tftpl` and are rendered with
`templatefile()`.

## 3. Block layout and comments

Inside a `resource` or `data` block, separated by blank lines:

1. `count` or `for_each`, then `provider`;
2. arguments, alphabetical (the tag or label argument included);
3. nested and `dynamic` blocks, alphabetical by block name, `timeouts` last;
4. `lifecycle`: `create_before_destroy`, `ignore_changes`,
   `replace_triggered_by`, `precondition`, `postcondition`, in that order;
5. `depends_on`, only with a comment saying why the reference graph is not
   enough.

Variables: `description`, `type`, `default`, `nullable`, `sensitive`,
`validation`. Outputs: `description`, `value`, `sensitive`, `precondition`.

Comments use `#`. Every file starts with the Apache-2.0 license header
(`make check-headers`; `make fix-headers` adds it), then a comment of one to
three lines: what the block is and why it exists, with a link to the
contract or the cloud's documentation where one explains the choice. Inline comments
explain why, never what. `terraform fmt` and `tofu fmt` output is the only
accepted formatting.

## 4. Language subset

The modules run on Terraform and OpenTofu. `required_version = ">= 1.5.0"`
in the module. Tests need Terraform 1.7+ or OpenTofu 1.8+ (mock providers)
and run on the runtimes the Makefile pins (the CAPTF base images).

MUST NOT use: variable validations that refer to other variables (Terraform
1.9+), `templatestring`, `ephemeral` resources and write-only arguments,
provider-defined functions, OpenTofu-only features (`.tofu` files,
provider `for_each`, `enabled`, early variable evaluation, state
encryption), `timestamp()`, `uuid()` and `plantimestamp()`.

Checks that span variables go in a `lifecycle.precondition` on the role's
primary resource, or in a `postcondition` on the data source that reads the
value.

Use `try()`, `can()` and `lookup()` for values that may be null or absent.
A conditional evaluates only the branch it chooses, so
`x == null ? null : f(x)` is safe on every supported runtime (checked on
Terraform 1.5.7 and 1.16.4 and OpenTofu 1.6.3 and 1.12.6). Both branches
must still convert to one type: to choose between differently shaped
objects, index a tuple instead. `&&` and `||` do NOT short-circuit on the
floor runtimes: guard their operands with `coalesce(var.x, "-")` or
`try()`.

Never call `base64decode()` on `var.bootstrap_data` outside a conditional
that has ruled out gzip (`!startswith(var.bootstrap_data, "H4sI")`, the
base64 of the gzip magic) and established a text format (cloud-config, or
Ignition JSON): a gzip payload makes it fail.

## 5. Versions and lock files

- Providers are pinned exactly (`version = "6.67.0"`), never with a range.
- No lock file is committed: `.gitignore` excludes `**/.terraform.lock.hcl`,
  and every `init` (Makefile, CI) resolves the exact pins of `versions.tf`
  afresh on a staged copy of the module, which is thrown away with the
  stage. One lock file could not serve both runtimes anyway: Terraform
  drops entries for registry hosts the configuration does not use, and
  OpenTofu's provider builds have different hashes.
- CAPTF never reads a module's lock file at run time: the controller
  generates the root module, and the image's provider mirror plus the exact
  pin decide what runs.
- A provider upgrade is its own commit: bump the pin, `make verify`.

## 6. Naming cloud resources

`locals_names.tf` derives every cloud resource name from the objects' keys,
with a hash that keeps truncated names unique:

```hcl
locals {
  cluster_key  = "${var.captf_cluster.namespace}/${var.captf_cluster.name}"
  cluster_hash = substr(sha256(local.cluster_key), 0, 8)
  # <cloud limit> - 9 leaves room for "-" and the hash.
  name_prefix = "${trimsuffix(substr("captf-${var.captf_cluster.namespace}-${var.captf_cluster.name}", 0, local.name_max - 9), "-")}-${local.cluster_hash}"
}
```

- The hash is always appended: `a-b`/`c` and `a`/`b-c` would otherwise
  collide.
- Lowercase `[a-z0-9-]`, then the cloud's own rule on top.
- Names a cloud controller manager matches on (instance names, hostnames)
  use `machine_name`, made valid for the cloud. Each such exception is
  documented in the README.

## 7. Tags and labels

```hcl
locals {
  captf_tags = { for k, v in var.captf_tags : <cloud key mapping> => <cloud value mapping> }
  tags       = merge(var.additional_tags, local.cloud_tags, local.captf_tags)
}
```

- The contract requires `captf_tags` on every resource that supports tags
  or labels. The captf keys merge last, so `additional_tags` cannot
  override them. `local.cloud_tags` holds tags a cloud controller manager
  requires (AWS `kubernetes.io/cluster/<id> = owned`).
- `additional_tags` validation rejects keys that collide with captf or
  cloud keys after mapping, case-insensitively where the cloud is.
- The key mapping is deterministic, injective and documented in the README
  "Tags" section, because `captf.io/<key>` is not valid everywhere:

  | Cloud | Mapping | Example |
  | --- | --- | --- |
  | AWS | unchanged | `captf.io/cluster` |
  | GCP labels | lowercase; `.` to `-`; other invalid characters to `_`; values lowercase, at most 63 characters (longer: 54 characters, `-`, 8 hex of sha256) | `captf-io_cluster` |
  | Azure | `/` to `_` | `captf.io_cluster` |
  | OCI free-form | `.` and space to `_`; at most 10 tags per resource, so `additional_tags` takes at most 4 | `captf_io/cluster` |
  | OpenStack | Nova metadata: `/` to `:`; Neutron and Octavia `tags`: `"<key>=<value>"` strings | `captf.io:cluster` |

- Every taggable resource sets its tag argument to `local.tags` (or a
  superset built from it), and so does every nested taggable: volume tags,
  launch template tag specifications, VNIC details, instance
  configurations. Provider-level default tags and labels are not used:
  they do not reach everything (AWS Auto Scaling launches) and mocked tests
  cannot see them.
- `hack/check-tags.sh` reads the provider schema and fails when a resource
  type that has the cloud's tag attribute does not set it from
  `local.tags`. `hack/tags.json` lists exempt types with a reason.
- Resource types that cannot carry tags are listed in the README.

## 8. Variables

- Contract inputs use exactly the contract's names and types. Inputs the
  controller always sets have no default; nullable inputs default to null.
  `captf_contract` validates `== "v1alpha1"`. A contract input a role does
  not use carries `# tflint-ignore: terraform_unused_declarations`.
- `captf_cluster_outputs`: the cluster role declares it with
  `default = null` and never reads it; machine and machinepool declare it
  without a default.
- User variables: a `description` is mandatory (one sentence, plus why the
  default is what it is). Types are precise; `any` only for exports. Every
  user variable has a default. A value the module cannot guess (a subnet,
  an image) is required by `default = null` plus a validation whose message
  says which `spec.variables` entry to set.
- `nullable = false` on collections and booleans. `sensitive = true` on
  secrets. Defaults are secure: private load balancers, no public IPs, no
  SSH, encryption on, instance metadata v1 off.
- Nodes of one cluster accept all traffic from each other, scoped to the
  cluster's own security group, network tag, service account or
  application security group, so any CNI works without port lists. Nothing
  else is open by default except the API port from the load balancer.
- Names are snake_case in the cloud's vocabulary (`vpc_id`, `compartment_id`).
  Booleans are positive (`spot`, `api_load_balancer_public`). Units are
  suffixes (`_gib`, `_seconds`, `_percent`).
- Every `error_message` starts with the variable's name (`subnets must …`),
  states the rule, and ends with a period.
- One name per concept across the `terraform-*` repositories; a cloud's own term
  replaces `<cloud term>`:

  | Concept | Variable |
  | --- | --- |
  | Public API load balancer | `api_load_balancer_public` |
  | API client allowlist | `api_allowed_cidrs` |
  | Static private API address | `api_load_balancer_private_ip` |
  | Kubernetes distribution | `distribution` (`"kubeadm"` or `"rke2"`) |
  | SSH allowlist (where SSH is reachable at all) | `ssh_allowed_cidrs` |
  | Bring-your-own node identities | `control_plane_<cloud term>`, `worker_<cloud term>` |
  | Spot capacity | `spot`, or the cloud's term (`preemptible`) |
  | Public node address | `public_ip` |
  | Extra network groups | `additional_<cloud term>_ids` |
  | Image name placeholders | `{version}` (`v1.31.4`), `{semver}` (`1.31.4`), and the cloud's slug forms where names cannot hold dots |
  | Boot disk | `<cloud term>_size_gib`, `<cloud term>_type`, `<cloud term>_kms_key_id` |
  | Autoscaling, target tracking | `autoscaling_target_cpu_percent` |
  | Autoscaling, threshold rules | `autoscaling_scale_out_cpu_percent`, `autoscaling_scale_in_cpu_percent` |
  | Staged bootstrap delivery | `bootstrap_delivery` (`"<store>"` or `"inline"`) |
  | Extra tags or labels | `additional_tags` |
  | Externally managed cluster | `external_cluster_exports` |

## 9. Outputs

- Every output has a `description`; contract outputs link to the contract.
- Values come from resource or data attributes that a refresh updates, and
  are wrapped in `try(..., null)` where a resource can vanish, so
  `apply -refresh-only` never errors.
- A resource whose disappearance outputs, exports or health must see uses
  `count` (`count = 1` when it always exists) and is read as
  `one(r[*].a)` or `try(r[0].a, null)`. A bare resource that a refresh
  drops from state reads as unknown, which `try()` cannot catch; a counted
  one reads as an empty tuple.
- Data sources must not fail once a brought resource is gone, because
  `destroy` refreshes them too: prefer listing or plural reads that return
  empty, and check brought inputs with preconditions, which a destroy
  skips.
- `provider_id_list` wraps its expression directly in `sort(...)`.
- Non-contract outputs live in `outputs_extra.tf` and never start with
  `captf_`.

## 10. Health

```hcl
locals {
  # <cloud> <resource> state -> contract health ("health" in common.md).
  health_by_state = {
    RUNNING = { state = "running", healthy = true, reason = null }
    # ...every documented cloud state, explicitly, each with its reason...
  }
  health_reading = lookup(local.health_by_state, upper(<state attribute>), { state = "unknown", healthy = false, reason = "UnknownState" })
}
```

- `message` names the cloud state; `reasons` is `[]` when healthy and
  stable machine-readable reasons otherwise.
- In every role, a primary resource that is gone, or a state that means
  deletion, is `terminated` with reason `<Kind>NotFound`.
- Cluster health comes from the cluster's own resources (the API load
  balancer), never from backend members: cluster health feeds `Ready`, and
  members are unhealthy during every normal control-plane bring-up.
- Machine health comes from the instance state.
- Pool health, in this order: the group is gone → `terminated`; desired
  capacity 0 → `running`, healthy; no members yet → `pending` with reason
  `NoMembers`; any member degraded, stopped or unknown → the worst of those
  three, with one `<Reason>:<instance>` per affected member; otherwise
  `running`, healthy only when the member count equals the desired capacity
  and every member runs, with the starting members named and
  `ScalingInProgress` on a count mismatch. A starting member never makes
  the pool `pending` (machinepool.md "Deriving group health"). A member
  whose state means deletion is not a member.

## 11. provider_id, addresses, failure domains, interruptible

- `provider_id` is exactly the format the cloud's controller manager writes
  to `Node.spec.providerID`. The README cites the controller source.
- `addresses` mirror what the cloud controller manager reports.
- `failure_domain` equals the input when one is given. With a null input
  the module picks deterministically:
  `names[parseint(substr(sha256(var.machine_name), 0, 8), 16) % length(names)]`
  over the sorted failure-domain names.
- `interruptible` reflects the spot or preemptible setting of the instance.
  Control-plane machines refuse spot capacity with a precondition.

## 12. Exports and the API endpoint

The cluster role's `exports` output is an object:

```hcl
exports = {
  schema          = "captf.io/<cloud>-cluster/v1"
  region          = ...
  failure_domains = { "<name>" = { <attribute> = "<string>" } }
  api = { # null when the endpoint is user-supplied
    host = "..."
    port = 6443
    # registration targets, keyed kube_apiserver and rke2_supervisor where
    # the cloud has one per listener, each { <id> = "...", port = <backend port> }
  }
  # cloud-specific ids
}
```

- Numbers are integers; nothing is secret (exports are stored in clear and
  copied into every machine's inputs).
- Adding a key keeps the schema; renaming or removing one bumps it to `v2`.
- The kube-apiserver backend port is `cluster_network.api_server_port`
  (default 6443) with kubeadm, and always 6443 with RKE2, whose supervisor
  listens on 9345 (control-planes/rke2.md); an `api_server_port` of 9345
  with RKE2 fails a precondition.
- Machine and machinepool validate `captf_cluster_outputs.schema`. An empty
  object means an externally managed TerraformCluster; the role then uses
  the user variable `external_cluster_exports`, which has the same schema,
  and fails a precondition with an actionable message when it is unset.
- `terraform_data.api_endpoint_guard` records, when the load balancer is
  created, every input that decides the endpoint (visibility, subnets,
  port, address), with `ignore_changes = [input]`. One postcondition fails
  any later plan that would change them, whether in place or by
  replacement: "The API endpoint of this cluster is fixed once its load
  balancer exists: <input> cannot change (recorded <x>, requested <y>).
  Revert the change, or create a new cluster." CAPTF's destructive-plan
  guard catches replacements only, and an operator can approve those.

## 13. Bootstrap data

- `bootstrap_format` validates against `cloud-config` and `ignition`.
  Gzipped Ignition fails a precondition.
- `bootstrap_data` is the base64 of the bootstrap Secret. Pass it unchanged
  to an argument that takes base64. Decode it only as section 4 allows.
- A precondition enforces the cloud's user-data size limit on what is sent.
- Where instance user data is readable outside the instance, a
  control-plane payload (it holds the cluster CA keys) is staged in a store
  the instance identity can read, behind
  `bootstrap_delivery = "<store>" | "inline"` with the store as default.
  The stub in user data is a plain `#cloud-boothook` script that fetches
  the payload once, gunzips it, accepts only `#cloud-config` or
  `## template: jinja` followed by `#cloud-config`, and installs it as
  `/etc/cloud/cloud.cfg.d/99-captf-bootstrap.cfg`, mode 0600, through a
  temporary file in the same directory. cloud-init re-reads
  `cloud.cfg.d` after its boothooks and before its modules; an
  `x-include-url` of the fetched file does not work, because cloud-init
  resolves includes before any boothook runs. Clouds without such a store
  document the exposure.
- Machine pools render `node_labels` themselves (the contract requires it)
  with one shared shell fragment: for each of `/etc/default/kubelet` and
  `/etc/sysconfig/kubelet` whose directory exists, it replaces a block
  marked `# captf-node-labels` with a `KUBELET_EXTRA_ARGS` line that keeps
  the existing value and appends `--node-labels=<sorted labels>`, and it
  writes `/etc/rancher/rke2/config.yaml.d/50-captf-node-labels.yaml` with
  `node-label+:`. The fragment runs in the staging stub where there is one,
  otherwise in the first `text/cloud-boothook` part of a MIME message whose
  second part is the bootstrap payload as an opaque base64 part
  (`application/x-gzip` when gzipped). Labels the NodeRestriction admission
  plugin forbids are dropped and listed in the `dropped_node_labels`
  output. Ignition with labels fails a precondition.
- A bootstrap rotation updates the pool's launch configuration in place and
  never replaces running instances.
- A `kubernetes_version` change, compared verbatim (a `+rke2rN` bump
  included), rolls the instances through
  `terraform_data.kubernetes_version_roll` or the cloud's own rolling
  update. Any other change that replaces instances is listed under the
  README's "Exceptions". Zones a pool inherits from the cluster are pinned
  at its first apply, so a cluster zone change never replaces instances.
- With autoscaling enabled, the scaling group's desired count is not reset
  by an apply.

## 14. Tests

`tests/<role>.tftest.hcl` at the repository root, plus
`tests/<role>_<topic>.tftest.hcl` when a file grows long; validation runs
may live in `tests/<role>_validation.tftest.hcl`. Each file has one
`mock_provider` per provider and alias, with inline `mock_resource` and
`mock_data` defaults for the computed attributes the module reads (ids in
the cloud's format, states, addresses), a top-level `variables {}` with
every contract input, then `run` blocks.

Run names are fixed so reviewers can find them:

- every module: `happy_path` (apply; every output asserted),
  `tags_on_taggable_resources`, `reapply_is_stable` (a second identical run
  keeps every id), and one `expect_failures` run per validation and
  precondition, named `invalid_<variable>` or `rejects_<condition>`;
- cluster role: `user_endpoint_skips_load_balancer`, `api_server_port_override`,
  `public_requires_allowed_cidrs`, `exports_shape`, `node_identity_byo`,
  and one `rejects_<input>_change` per input the endpoint guard records;
- machine role: `control_plane_registers_backend`, `worker_has_no_backend`,
  `failure_domain_requested`, `failure_domain_defaulted`,
  `unknown_failure_domain`, `spot_is_interruptible`,
  `rejects_spot_control_plane`, `externally_managed_without_override`,
  `externally_managed_with_override`, `wrong_exports_schema`,
  `bootstrap_<format>`, `bootstrap_too_large`, and `health_<contract state>`
  for each contract state the role can reach (extra runs per cloud state
  are welcome);
- machinepool role: `autoscaling_disabled`, `autoscaling_enabled`,
  `bootstrap_rotation_in_place`, `kubernetes_version_rolls`,
  `kubernetes_version_suffix_rolls`, `node_labels_rendered`,
  `node_labels_unsupported_format`, `bootstrap_too_large`,
  `zero_replicas_healthy`, `membership_excludes_terminated`,
  `failure_domains_default_to_cluster`.

"Updated in place" is asserted by id stability across runs: never pin `id`
in a mock default for a resource whose replacement a test asserts.
OpenTofu's mock ids are known at plan time and fixed per address, so prove
a replacement on Terraform with a sentinel id and say in a comment that the
OpenTofu run checks less.

Every test passes on both runtimes. Avoid what differs between them:
`override_during`, `state_key`, `parallel`, mock `source` files, function
calls inside override values, nested values Terraform's mock cannot
convert, assertions on generated random values, instance keys in
`override_*` targets (OpenTofu rejects them and overrides every instance),
mock defaults for attributes the configuration sets (OpenTofu rejects
them), and `run.<name>` in `assert` (on OpenTofu, pass the directly
preceding run's outputs through `variables` instead).

## 15. Quality gates

The host needs `make`, `podman` (or `docker` with `ENGINE=docker`), `jq` and
Go (for tfcapi-lint). Every other tool runs in a container pinned by digest.
The Makefile has no `lock`, `build` or `test` target: nothing here builds an
image (section 16).

| Target | Checks |
| --- | --- |
| `check-headers` | the Apache-2.0 license header on every source file (`.licenserc.yaml`); `fix-headers` adds it |
| `fmt-check` | `terraform fmt -check` and `tofu fmt -check`, recursive; `fmt` formats in place |
| `check-conventions` | `hack/check-layout.sh` (sections 2 and 4, after its `--self-test` against `hack/testdata`) and `hack/check-tags.sh` (section 7) |
| `shellcheck` | `hack/check-shell.sh`: shellcheck over `hack/` scripts and every shell template, rendered with placeholders; a template counts as shell when it starts with a shebang or `#cloud-boothook` or carries a `# shellcheck shell=` directive. Every `disable` names its reason |
| `validate` | `init` and `validate` on Terraform 1.16.5 and OpenTofu 1.12.7, and on the floors Terraform 1.5.7 and OpenTofu 1.6.3 |
| `unit-test` | `test` on Terraform 1.16.5 and OpenTofu 1.12.7; skips when there is no `tests/*.tftest.hcl` |
| `tflint` | tflint with the terraform ruleset (preset `all`) and the cloud ruleset where one exists |
| `tfcapi-lint` | `tfcapi-lint module --role <role> --strict`; allowed warnings live in the Makefile with a reason and in the README "Exceptions" |
| `scan` | `trivy config`; every ignore in `.trivyignore.yaml` carries a reason |
| `verify` | all of the above; the groups that share no cache (static checks, one per runtime) run in parallel |
| `clean` | removes `build/` (the staged module and schemas); keeps `.cache/` and `.tools/` |

`RUNTIMES` selects the runtimes (`make validate RUNTIMES=opentofu`).
`tfcapi-lint` is built from the provider repository (`PROVIDER_DIR`, which
defaults to `../cluster-api-provider-terraform` and which CI checks out
into `.cache/provider`); without a checkout or a `TFCAPI_LINT` binary it
skips itself and prints that it did.

## 16. Images

Not applicable: these repositories hold the module and its checks only, and
build no images, Dockerfiles or smoke tests. CI covers the code alone. The
module images (`ghcr.io/captf-io/<cloud>-<role>`) are built elsewhere, by
the `<cloud>-modules` repositories. The image contract of
<https://captf.io/docs/module-author/contract/v1alpha1/> (paths, labels,
inputs, outputs) still binds the module, and `tfcapi-lint module` checks
the part that lives in source.

## 17. Documentation

The README has the H1 `terraform-<provider>-<role>` and these sections, in
this order: Usage (the module image, the Terraform Registry address
`captf-io/<role>/<provider>` and what calling it directly implies),
What it creates (resource table), Prerequisites (network,
quotas, the permissions the identity needs, image requirements), Inputs
(contract inputs used; user variables table), Outputs, Exports, Identity
Secret, Lifecycle (machinepool: what updates in place and what rolls),
Bootstrap (machine and machinepool), Tags, Health, any cloud-specific
sections, Limitations, Exceptions, Examples, Development (the host tools
and the `make` targets).

Links in the README are absolute (`https://github.com/captf-io/<repo>/blob/main/...`):
the Terraform Registry renders it as the module's page, where relative
links break.

A release is a signed `vX.Y.Z` tag on `main`; the Terraform Registry
publishes every semantic-version tag as a module version within a minute
of the push. Versions follow the CAPTF release they were cut with.

`DESIGN.md` is specific to the repository's role and has exactly these
top-level sections: Scope, Decisions, Exports, Unverified, Rejected
alternatives. It records each decision with the evidence behind it, the
alternatives rejected, and the facts not yet verified against a real cloud.

`examples/` has a `README.md`, an identity Secret, and manifests that use
the module image, pinned to a release tag (`vX.Y.Z-<runtime>`), never a moving
one; the README does the same. A MachineHealthCheck's
`InfrastructureReady` timeout exceeds the apply time plus one drift
interval (2700 seconds with the default 30-minute interval).
