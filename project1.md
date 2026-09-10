# Project 1: Kubernetes Feature Demo on AWS EKS

## About

This project is an end-to-end, hands-on demo of core Kubernetes objects — Pods,
ReplicaSets, Deployments (scaling, rolling updates, rollback), Services
(ClusterIP + AWS Network Load Balancer), and Ingress (AWS Application Load
Balancer) — running on a real AWS EKS cluster, provisioned entirely through
Terraform. The application is a minimal Go web app ("Trailblazer Tours", a
small tour-shop UI) that reports which pod served each request, so you can
visually see load balancing, rollouts, and scaling happen in real time.

Everything here was built and deployed from scratch during a real working
session, including hitting (and fixing) the exact problems anyone doing this
for the first time on a constrained/free-tier AWS account is likely to hit.
The [Troubleshooting Guide](#troubleshooting-guide-lessons-from-this-build)
below documents every one of them with the actual fix, not theoretical advice.

## Tech Stack

| Layer | Tool / Service | Used for |
| --- | --- | --- |
| Cloud provider | AWS (EKS, EC2, VPC, ECR, IAM, S3, CodeBuild, Elastic Load Balancing) | All infrastructure |
| Infrastructure as Code | Terraform (`terraform-aws-modules/vpc`, `terraform-aws-modules/eks`) | Provisioning and destroying everything reproducibly |
| Container orchestration | Kubernetes (EKS-managed) | Running the app: Pods, ReplicaSets, Deployments, Services, Ingress |
| Cluster CLI | `kubectl` | Applying manifests, scaling, rollouts, debugging |
| Package manager for Kubernetes | Helm | Installing the AWS Load Balancer Controller |
| Ingress/LB controller | AWS Load Balancer Controller | Provisioning the NLB and ALB from Kubernetes objects |
| Application language | Go (standard library only) | Backend API + static file server |
| Frontend | Plain HTML/CSS/JS | "Trailblazer Tours" UI, no build step or framework |
| Container image build | AWS CodeBuild (Docker, privileged mode) | Building/pushing the image without a local container engine |
| Container image format | Dockerfile (multi-stage, distroless runtime) | Small, minimal-attack-surface image |
| Version control | Git + GitHub CLI (`gh`) | Publishing this repo |

## Components

| Component | Path | One-line description |
| --- | --- | --- |
| Infra (Terraform) | [infra/](infra) | VPC, EKS cluster + managed node group, ECR repo, CodeBuild project, AWS Load Balancer Controller IAM role. |
| Backend app | [app/backend/](app/backend) | Go HTTP server (stdlib only) serving a JSON API + static frontend from one binary/container. |
| Frontend | [app/backend/static/](app/backend/static) | Plain HTML/CSS/JS "tour shop" UI with a live pod-identity badge — no build step, no framework. |
| Kubernetes manifests | [app/k8s/](app/k8s) | Namespace, standalone ReplicaSet (teaching-only), Deployment, ClusterIP Service, NLB Service, ALB Ingress — numbered in apply order. |
| Image build | [infra/codebuild.tf](infra/codebuild.tf) | AWS CodeBuild project that builds/pushes the Docker image with zero local container engine required. |
| Windows jump host | [IAC/Terraform/terraform-devops-labs/wind-client](../../IAC/Terraform/terraform-devops-labs/wind-client) | Optional disposable EC2 Windows box, pre-loaded with the toolchain, used to test the deployed app and stage a GitHub push — not required to deploy. |
| Command reference | [workflow.md](workflow.md) | Copy-paste sequential command list for the whole deployment. |

## What You'll Learn

- How a Deployment owns a ReplicaSet, which owns Pods — and what breaks when you manage a ReplicaSet directly instead.
- Why `Service` selectors are inclusive-match, not exact-match, and how that can leak traffic to pods you didn't intend to expose.
- The difference between a `Service type=LoadBalancer` (NLB, via Service annotations) and an `Ingress` (ALB, via the AWS Load Balancer Controller) — and that **both** require the controller to be installed; neither is "simpler" than the other in that regard.
- IRSA (IAM Roles for Service Accounts): how a Kubernetes ServiceAccount assumes a real IAM role via OIDC federation, scoped with `sts:AssumeRoleWithWebIdentity` conditions.
- Why small EC2 instance types have a **hard pods-per-node ceiling** driven by ENI/IP address limits — not just CPU/memory — and how that interacts with rolling update strategies.
- How to build and push a container image with **zero local Docker/Podman install**, using AWS CodeBuild in privileged mode.
- Why Terraform deliberately ignores certain drift (like node group `desired_size`) via `lifecycle.ignore_changes`, and how to scale around it with the AWS CLI.
- A concrete example of splitting responsibility between Terraform (cloud infrastructure) and `kubectl`/`helm` (cluster-internal objects) in one project.

## How Infra Is Deployed

All of this runs from your local machine (Terraform + AWS CLI installed there) — see [infra/README.md](infra/README.md) for the full variable/output reference.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
- `cluster_endpoint_public_access_cidrs` — restrict from the default `["0.0.0.0/0"]` to your own IP (`curl https://checkip.amazonaws.com`), in `/32` form. **Do not use `/0`** — that's the entire internet, not one IP.
- `node_instance_types` — if your account is Free-Tier-restricted, use `["t3.micro"]` (see troubleshooting below).
- `image_source_bucket` — the S3 bucket that will hold `project1.zip` for CodeBuild's source (created by the `wind-client` stack; see its output `transfer_bucket_name`).

```bash
terraform init
terraform plan
terraform apply
```

Creates the VPC (2 AZs, 1 NAT gateway), EKS cluster + managed node group, ECR repository, a CodeBuild project (for image builds without local Docker), and the IAM role for the AWS Load Balancer Controller. Takes 15-25 minutes.

```bash
aws eks update-kubeconfig --region "$(terraform output -raw aws_region)" --name "$(terraform output -raw cluster_name)"
kubectl get nodes
```

## How the Backend Is Deployed

The Go app has no external dependencies, so building it is just `go build` — but producing a **Linux container image** from a Windows machine without Docker Desktop needs a different path. This project uses **AWS CodeBuild** (Docker available inside AWS's managed build environment, privileged mode):

```bash
aws codebuild start-build --project-name "$(terraform output -raw codebuild_project_name)" --region ap-south-1
aws codebuild list-builds-for-project --project-name "$(terraform output -raw codebuild_project_name)" --region ap-south-1 --query "ids[0]" --output text
aws codebuild batch-get-builds --ids "<id-from-above>" --region ap-south-1 --query "builds[0].{status:buildStatus,phase:currentPhase}"
```

CodeBuild pulls its source from the S3 bucket holding `project1.zip` (see `image_source_bucket`), runs the Dockerfile in `app/backend`, and pushes to ECR — no Docker, Podman, or admin rights needed on your machine at all.

Then point the manifests at the real image:

```bash
cd ../app
ECR_REPOSITORY="$(terraform -chdir=../infra output -raw ecr_repository_url)"
sed -i "s#<ACCOUNT_ID>\.dkr\.ecr\.<REGION>\.amazonaws\.com/k8s-demo#${ECR_REPOSITORY}#" k8s/02-deployment.yaml k8s/01-replicaset-demo.yaml
```

## How Kubernetes Is Deployed

1. **Install the AWS Load Balancer Controller** (required for both the NLB Service and the ALB Ingress — see troubleshooting below for why this isn't optional):

   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n kube-system \
     --set clusterName="$(terraform -chdir=../infra output -raw cluster_name)" \
     --set region=ap-south-1 \
     --set vpcId="$(terraform -chdir=../infra output -raw vpc_id)" \
     --set replicaCount=1 \
     --set serviceAccount.create=true \
     --set serviceAccount.name=aws-load-balancer-controller \
     --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$(terraform -chdir=../infra output -raw lb_controller_role_arn)"
   ```

   `replicaCount=1` (not the chart default of 2) matters on small node pools — see troubleshooting.

2. **Apply the manifests, in order:**

   ```bash
   kubectl apply -f k8s/00-namespace.yaml
   kubectl apply -f k8s/02-deployment.yaml
   kubectl apply -f k8s/03-service-clusterip.yaml
   kubectl apply -f k8s/04-service-loadbalancer.yaml
   kubectl apply -f k8s/05-ingress.yaml
   kubectl get pods,svc,ingress -n k8s-demo -o wide
   ```

3. **Open the app** at either the NLB or ALB hostname shown above — you'll see the tour-shop UI with a live "Served by" badge showing `pod_name`/`pod_ip`/`node_name`, refreshing every few seconds.

## Demo Script

```bash
kubectl scale deployment k8s-demo -n k8s-demo --replicas=5
kubectl set env deployment/k8s-demo -n k8s-demo APP_VERSION=v2 && kubectl rollout status deployment/k8s-demo -n k8s-demo
kubectl rollout undo deployment/k8s-demo -n k8s-demo
kubectl apply -f k8s/01-replicaset-demo.yaml && kubectl scale rs k8s-demo-rs -n k8s-demo --replicas=5
```

The standalone ReplicaSet's pods use `app: k8s-demo-standalone` (not `app: k8s-demo`), so the Services never route live traffic to them — its traffic stays observably separate from the real Deployment.

## Troubleshooting Guide (Lessons From This Build)

Every one of these actually happened while building this project — not hypothetical.

### 1. Windows `Compress-Archive`/`ZipFile` stores backslash paths, breaking Linux extraction

**Symptom:** CodeBuild failed with `Error while executing command: cd project1/app/backend. Reason: exit status 2` — directory didn't exist after extraction.

**Cause:** Windows PowerShell 5.1 (.NET Framework) `System.IO.Compression.ZipFile`/`Compress-Archive` writes zip entry names with `\` instead of the ZIP-spec-required `/`. Windows tools tolerate this; Linux extractors (CodeBuild's) create flat files with literal backslashes in their names instead of nested folders.

**Fix:** Build the zip file entry-by-entry manually, explicitly replacing `\` with `/` in each entry name:

```powershell
$entryName = $relativePath.Replace('\', '/')
```

Never trust `Compress-Archive` output for anything that will be extracted on Linux.

### 2. AWS account restricted to Free-Tier-eligible EC2 instance types only

**Symptom:** `terraform apply` failed creating the node group: `InvalidParameterCombination - The specified instance type is not eligible for Free Tier.`

**Cause:** New/trial AWS accounts can be restricted to `t2.micro`/`t3.micro` only — even for EKS worker nodes. `t3.small`, `t3.medium`, etc. are all rejected the same way (this is an account-level EC2 restriction, not a Terraform issue).

**Fix:** Set `node_instance_types = ["t3.micro"]` in `terraform.tfvars`. Confirm exactly what's allowed with:
```bash
aws ec2 describe-instance-types --filters "Name=free-tier-eligible,Values=true" --region <region> --query "InstanceTypes[].InstanceType" --output table
```

### 3. Editing `node_desired_size` in Terraform did nothing

**Symptom:** Changed `node_desired_size` in `terraform.tfvars`, ran `terraform plan` — "No changes. Your infrastructure matches the configuration."

**Cause:** The `terraform-aws-modules/eks` managed-node-group submodule sets `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` deliberately, so Terraform doesn't fight a cluster autoscaler or manual scaling.

**Fix:** Scale the running node count directly via AWS CLI (Terraform still owns `min_size`/`max_size`):
```bash
aws eks update-nodegroup-config --cluster-name <cluster> --nodegroup-name <nodegroup> --scaling-config minSize=2,maxSize=4,desiredSize=4 --region <region>
```

### 4. `t3.micro` hard-caps pods per node — "Too many pods", not a resource shortage

**Symptom:** `FailedScheduling: 0/3 nodes are available: 3 Too many pods.` — happened even with plenty of free CPU/memory.

**Cause:** The AWS VPC CNI plugin caps pods-per-node based on **ENI/IP address limits**, not compute capacity. For `t3.micro`: 2 ENIs × 2 IPs each = max **4 pods per node total**, including every system DaemonSet pod (`kube-proxy`, `aws-node`, `coredns`). This can't be fixed with resource requests/limits — it's a hard ceiling tied to instance size.

**Fix:** Add more (small) nodes rather than expecting bigger pods to fit — or reduce what else runs on each node (see #5).

### 5. AWS Load Balancer Controller's default 2 replicas silently ate node capacity

**Symptom:** After installing the AWS Load Balancer Controller via Helm, a 3rd app pod could never schedule, even after freeing a slot elsewhere.

**Cause:** The Helm chart defaults to `replicaCount: 2` (for HA). Both replicas landed on the same node, consuming both of its remaining pod slots (per the #4 ceiling) — leaving zero room for an app pod on that node.

**Fix:** For a lab/demo, `--set replicaCount=1` on the Helm install. In production, this is a real trade-off between controller HA and node capacity — size accordingly.

### 6. Deployment rollout deadlocked at "1 out of 3 new replicas"

**Symptom:** `kubectl rollout restart` got permanently stuck; `kubectl describe pod` on the new pod showed the same `Too many pods` error, and the old pod was never terminated either.

**Cause:** The Deployment's `rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }` strategy requires spare capacity for an *extra* pod during the transition (zero-downtime rollout). With zero spare node capacity (see #4), the new pod could never schedule — so it never became `Ready` — so the old pod, protected by `maxUnavailable: 0`, was never allowed to terminate. A genuine deadlock.

**Fix:** Changed the strategy to `maxSurge: 0, maxUnavailable: 1` — terminates an old pod *before* creating the new one, fitting within existing capacity (accepting a brief per-pod gap, fine for a demo). To unstick an already-deadlocked rollout without waiting for a manifest change:
```bash
kubectl patch deployment <name> -n <ns> -p '{"spec":{"strategy":{"rollingUpdate":{"maxUnavailable":1,"maxSurge":0}}}}'
```

### 7. `Service type=LoadBalancer` stuck at `<pending>` forever

**Symptom:** `kubectl get svc` showed `EXTERNAL-IP: <pending>` indefinitely; `kubectl describe svc` showed only generic `EnsuringLoadBalancer` events from `service-controller`, never resolving.

**Cause:** The annotation `service.beta.kubernetes.io/aws-load-balancer-type: external` specifically opts into the **AWS Load Balancer Controller** — the legacy in-tree/cloud-controller-manager path doesn't understand that value and just retries forever without ever succeeding or failing loudly. Both the NLB (Service) and ALB (Ingress) paths in this project **require** the controller to be running; neither is the "simpler, no-controller-needed" option.

**Fix:** Install the AWS Load Balancer Controller (see "How Kubernetes Is Deployed" above) before applying either `04-service-loadbalancer.yaml` or `05-ingress.yaml`.

### 8. Docker Desktop / Podman don't work on Windows Server EC2

**Symptom:** N/A — avoided by design, but worth stating: both require a Linux VM backend (WSL2/Hyper-V), which standard (non-metal) EC2 instances typically can't run (no nested virtualization).

**Fix:** Use AWS CodeBuild for image builds instead of trying to install a container engine on a Windows Server jump host.

### 9. AWS credentials don't carry across terminal sessions/windows

**Symptom:** `aws`/`kubectl`/`terraform` commands failed with `Unable to locate credentials` in a newly opened terminal, despite working moments earlier elsewhere.

**Cause:** `$env:`/`export`-based credentials are session-scoped; a new terminal or window starts with nothing.

**Fix:** Persist with `aws configure` (writes to `~/.aws/credentials`), which every shell/terminal can read — no more re-exporting per session. Newly installed tools (`kubectl`, `helm` via direct binary download) also need a fresh terminal to pick up PATH changes.

## Cleanup

```bash
kubectl delete -f app/k8s
kubectl get svc,ingress -n k8s-demo   # re-run until empty - avoids a stuck VPC delete
cd infra
terraform destroy
```

If you also stood up the Windows jump host:
```bash
cd ../../IAC/Terraform/terraform-devops-labs/wind-client
terraform destroy
```

Destroy promptly — the EKS control plane, NAT gateway, and load balancers all bill continuously while running.
