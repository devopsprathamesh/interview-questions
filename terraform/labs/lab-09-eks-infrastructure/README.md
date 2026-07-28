# Lab 9: Amazon EKS Infrastructure

## Objective
Provision a genuinely working EKS cluster with a managed node group, using the `eks` module built for this lab, wired into the `vpc` module from Lab 8, and demonstrate the modern Pod Identity access pattern end to end with a real, deployed workload.

## Scenario
A platform team needs a reference EKS cluster: private-subnet nodes, no `aws-auth` ConfigMap (access entries only), Pod Identity for workload IAM access, and a conservative node-group update configuration that won't repeat the all-at-once eviction incident from [Question 55](../../interview-questions/06-kubernetes-eks.md#question-55-the-node-group-upgrade-that-evicted-everything-at-once).

## Skills Practised
- Cluster IAM roles, node IAM roles, and the specific policy attachments EKS requires
- `depends_on` for IAM-role-then-service-that-uses-it ordering
- Modern EKS access entries (no `aws-auth` ConfigMap at all)
- OIDC provider setup for IRSA, alongside EKS Pod Identity for new workloads
- Terraform-then-Kubernetes-provider dependency sequencing (see Troubleshooting Exercise)
- Managed node group `update_config` tuning

## Architecture
See [Diagram 13: EKS Infrastructure Architecture](../../diagrams/13-eks-architecture.md) for the full picture. This lab implements exactly that diagram: private-subnet nodes, a cluster-creator access entry (for break-glass recovery per [Question 56](../../interview-questions/06-kubernetes-eks.md#question-56-the-aws-auth-change-that-locked-everyone-out)), an OIDC provider, the Pod Identity Agent add-on, and one real Pod Identity association for a sample workload.

## Prerequisites
- [Lab 2](../lab-02-remote-state/) and [Lab 8](../lab-08-aws-networking/) completed (or at minimum, understand the `vpc` module's outputs, since this lab reuses it directly)
- `kubectl` installed locally
- **A real, budgeted willingness to incur EKS + EC2 cost for the duration of this lab** — see Cost Warning below. If you cannot incur any cost right now, do the **plan-only variant** described in Step 1.

## Directory Structure
```text
lab-09-eks-infrastructure/
├── README.md
├── versions.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── backend.hcl.example
└── terraform.tfvars.example

modules/eks/                # the reusable module this lab consumes
├── README.md, versions.tf, variables.tf, main.tf, outputs.tf
```

## Step-by-Step Tasks
1. **Cost-aware path check**: if you want to validate this lab's design without spending anything, stop after `terraform plan` in step 4 — the plan output alone demonstrates every IAM-role/dependency/access-entry concept without creating a single billable resource. Only proceed to `apply` if you're ready to incur real EKS + EC2 cost.
2. Copy `backend.hcl.example` → `backend.hcl` and `terraform.tfvars.example` → `terraform.tfvars`; set `lab_operator_cidr` to your own IP (`curl -s ifconfig.me`).
3. `terraform init -backend-config=backend.hcl`
4. `terraform plan` — read through every resource carefully, especially the `depends_on` edges and the access-entry principal ARN conversion in `modules/eks/main.tf`.
5. `terraform apply` (typically 10-15 minutes — EKS cluster creation is not instant).
6. `aws eks update-kubeconfig --name "$(terraform output -raw cluster_name)" --region us-east-1` (or use the `configure_kubectl` output directly).
7. `kubectl get nodes` — confirm both nodes show `Ready`.
8. `kubectl get pods -n kube-system | grep pod-identity` — confirm the Pod Identity Agent DaemonSet is running.

## Terraform Configuration
See [`main.tf`](main.tf) for the lab composition, and [`modules/eks/main.tf`](../../modules/eks/main.tf) for the reusable module.

## Commands to Execute
```bash
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
# edit both, including lab_operator_cidr
terraform init -backend-config=backend.hcl
terraform plan     # review thoroughly before proceeding
terraform apply
aws eks update-kubeconfig --name "$(terraform output -raw cluster_name)" --region us-east-1
kubectl get nodes
kubectl get pods -n kube-system
```

## Expected Output
`kubectl get nodes` shows 2 nodes in `Ready` status. `terraform output oidc_provider_arn` shows a valid OIDC provider ARN. The `aws_eks_pod_identity_association.sample_app` resource is created, associating the `default` namespace's `sample-app` service account with an S3-read-only IAM role.

## Validation
```bash
# Confirm access entries, not aws-auth ConfigMap, control access
aws eks list-access-entries --cluster-name "$(terraform output -raw cluster_name)"
kubectl get configmap aws-auth -n kube-system   # expected: NotFound - this cluster never uses it

# Confirm the Pod Identity association is real
aws eks list-pod-identity-associations --cluster-name "$(terraform output -raw cluster_name)"

# Confirm node group update_config is set conservatively
aws eks describe-nodegroup --cluster-name "$(terraform output -raw cluster_name)" \
  --nodegroup-name "$(terraform output -raw cluster_name)-nodes" --query 'nodegroup.updateConfig'
```

## Failure Injection
Deliberately remove the `depends_on` from `modules/eks/main.tf`'s `aws_eks_node_group.this` resource, then `terraform destroy` and `terraform apply` again from scratch several times. Depending on scheduling, you may observe nodes intermittently failing to register (per [Question 8](../../interview-questions/01-terraform-core.md#question-8-the-intermittent-iam-race)) — though this is probabilistic, not guaranteed on every run, which is exactly the point: intermittent failures without a clear pattern are a strong sign of a missing dependency edge, not a flaky provider.

## Troubleshooting Exercise
Try adding a `helm_release` resource directly to this same root module's `main.tf`, configuring the Helm provider from `module.eks`'s outputs, in the same apply that creates the cluster. Observe the fragility this creates on a from-scratch `apply` (per [Question 53](../../interview-questions/06-kubernetes-eks.md#question-53-the-provider-that-needed-a-cluster-that-didnt-exist-yet)) — then remove it and note why this repository deliberately keeps workload deployment in a separate configuration/state (per [Question 58](../../interview-questions/06-kubernetes-eks.md#question-58-one-state-or-two-for-cluster-and-workloads)).

## Cleanup
```bash
terraform destroy
```
**Chargeable resources — read before applying:** the EKS control plane bills hourly regardless of node count; the 2 `t3.medium` nodes bill standard EC2 rates; the NAT gateway (from `modules/vpc`) bills hourly plus data processing. **Verify current EKS/EC2/NAT pricing yourself** — do not leave this cluster running unattended. Destroy immediately after completing the validation steps; this lab should not run for more than an hour or two in one sitting.

## Interview Questions Connected to This Lab
- [Question 53: The provider that needed a cluster that didn't exist yet](../../interview-questions/06-kubernetes-eks.md#question-53-the-provider-that-needed-a-cluster-that-didnt-exist-yet)
- [Question 54: IRSA or Pod Identity?](../../interview-questions/06-kubernetes-eks.md#question-54-irsa-or-pod-identity)
- [Question 55: The node group upgrade that evicted everything at once](../../interview-questions/06-kubernetes-eks.md#question-55-the-node-group-upgrade-that-evicted-everything-at-once)
- [Question 56: The aws-auth change that locked everyone out](../../interview-questions/06-kubernetes-eks.md#question-56-the-aws-auth-change-that-locked-everyone-out)
- [Question 58: One state or two for cluster and workloads?](../../interview-questions/06-kubernetes-eks.md#question-58-one-state-or-two-for-cluster-and-workloads)

## Production Considerations
- `endpoint_public_access = true` is a lab convenience; production clusters should strongly prefer `false` with access via VPN/Direct Connect/a bastion, per [`modules/eks/README.md`](../../modules/eks/README.md).
- This lab's three-tier security group model (per [Question 57](../../interview-questions/06-kubernetes-eks.md#question-57-three-security-groups-one-cluster-one-incident-waiting-to-happen)) relies mostly on EKS's own automatically-managed cluster security group; a production cluster needing security-groups-for-pods would require additional launch-template and `SecurityGroupPolicy` configuration beyond this lab's scope — see the Advanced Challenge.
- A real platform would separate cluster infrastructure (this lab) from workload deployment (GitOps or a separate Terraform state) per [Question 58](../../interview-questions/06-kubernetes-eks.md#question-58-one-state-or-two-for-cluster-and-workloads) — this lab intentionally keeps them together only for teaching-sequence simplicity.

## Advanced Challenge
Add security-groups-for-pods for the `sample-app` workload: create a dedicated security group scoped to a specific AWS resource (e.g., restricting access to a specific RDS instance's security group), and apply it via a `SecurityGroupPolicy` Kubernetes manifest (using the `kubernetes` provider, in a **separate** Terraform configuration/state per the Troubleshooting Exercise's lesson) targeting pods labeled `app: sample-app`.
