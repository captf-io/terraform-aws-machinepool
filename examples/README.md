# Examples

| File | What it is |
| --- | --- |
| [`identity.yaml`](identity.yaml) | The credentials Secret (static keys, or a role to assume through shared config files) and the TerraformClusterIdentity that lets a namespace use it. Placeholder values. |
| [`identity-policy.json`](identity-policy.json) | An IAM policy for those credentials covering all three roles: read access, the security groups, instances and launch templates, the API load balancer, Auto Scaling groups, the node roles under `/captf/`, `iam:PassRole` for them, the service-linked roles, and the `captf-bootstrap-*` buckets. Replace `arn:aws:` for another partition, and extend `PassNodeRoles` to brought node roles (`control_plane_instance_profile`, `worker_instance_profile`) outside `/captf/`. |
| [`cluster-kubeadm.yaml`](cluster-kubeadm.yaml) | A kubeadm cluster: TerraformCluster, KubeadmControlPlane, a MachineDeployment and an autoscaled MachinePool on `ghcr.io/captf-io/module-images/aws-{cluster,machine,machinepool}:v0.1.0-opentofu`, and MachineHealthChecks for the workers (`InfrastructureReady` 2700 s) and the control plane (3600 s), both above apply time plus one 30-minute drift interval. |

The policy lets its holder write the policies of any role under
`/captf/` and launch instances with it, so whoever holds these credentials
can grant those roles anything; when the node roles carry
`node_role_permissions_boundary`, add an `iam:PermissionsBoundary` condition
to `iam:CreateRole`, `iam:PutRolePolicy` and `iam:AttachRolePolicy`, and
consider an `iam:PolicyARN` allow-list on `iam:AttachRolePolicy`. With a
customer managed `root_volume_kms_key_id`, the credentials also need
`kms:CreateGrant`, `kms:Decrypt`, `kms:GenerateDataKeyWithoutPlaintext`,
`kms:ReEncrypt*` and `kms:DescribeKey` on that key, unless its key policy
grants them.

The manifests pin every image to a release, `v0.1.0-opentofu`: change the
tag to the release you deploy (`vX.Y.Z-opentofu` or `vX.Y.Z-terraform`), or
to a digest. The moving tags (`opentofu`, `terraform`) are
for trying things out, never for anything you keep.

All three are templates for `clusterctl generate yaml --from <file>`;
each file's header lists its variables.

The policy has not been exercised against a real account yet: the first
apply of each role is the test (DESIGN.md "Unverified").
