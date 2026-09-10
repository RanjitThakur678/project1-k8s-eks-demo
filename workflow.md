# Deployment Workflow — Project 1 (Kubernetes Feature Demo on EKS)

Run everything below from the repo root (`c:\prac\My-code`) in Git Bash, in order. Steps marked **CHECKPOINT** require you to read output before continuing — don't blindly pipe the whole file to `bash`.

## 0. Credentials (one-time)

```bash
aws configure
aws sts get-caller-identity
```

## 1. Provision AWS infrastructure (VPC, EKS, ECR)

```bash
cd projects/project1/infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`: set `aws_region` if not `us-east-1`, and restrict `cluster_endpoint_public_access_cidrs` to your public IP (`curl https://checkip.amazonaws.com`).

```bash
terraform init
terraform plan
```

**CHECKPOINT** — review the plan (expect VPC, EKS cluster, node group, ECR repo — nothing else). Then:

```bash
terraform apply
```

This takes 15-25 minutes and starts billable resources (EKS control plane, EC2 nodes, NAT gateway).

## 2. Configure kubectl

```bash
aws eks update-kubeconfig --region "$(terraform output -raw aws_region)" --name "$(terraform output -raw cluster_name)"
kubectl get nodes
```

## 3. Build and push the app image — run on the Windows jump host

Docker Desktop isn't supported on Windows Server, so this step runs from the jump host using Podman (installed there), not locally. The jump host's IAM role now has ECR push permission (`aws_iam_role_policy_attachment.ecr_push` in `wind-client/main.tf`) — apply that once first:

```bash
cd ../../../IAC/Terraform/terraform-devops-labs/wind-client
terraform apply
```

Get the values the client needs (it can't read this Terraform state itself):

```bash
cd ../../../projects/project1/infra
terraform output -raw ecr_repository_url
terraform output -raw aws_region
```

Sync current source onto the client first (rebuild the zip if app/infra files changed since the last sync — see step 8's rebuild command):

```bash
cd ../../../IAC/Terraform/terraform-devops-labs/wind-client
aws s3 cp project1.zip "s3://$(terraform output -raw transfer_bucket_name)/project1.zip"
```

On the client: `aws s3 cp s3://<bucket>/project1.zip ...` then `Expand-Archive ... -Force` (see step 8 for exact commands).

**On the jump host** (Fleet Manager session), with the two values substituted:

```powershell
$EcrRepository = "<ecr_repository_url output>"
$Region = "<aws_region output>"
aws ecr get-login-password --region $Region | podman login --username AWS --password-stdin $EcrRepository
Set-Location C:\work\project1\app\backend
podman build -t "${EcrRepository}:latest" .
podman push "${EcrRepository}:latest"
```

(Requires `C:\work\project1` on the client to be up to date — re-run stage 8 first if you've changed app source since the last sync.)


## 4. Point the manifests at the real image

Run locally (you're already in `projects/project1/infra` after step 1):

```bash
ECR_REPOSITORY="$(terraform output -raw ecr_repository_url)"
cd ../app
sed -i "s#<ACCOUNT_ID>\.dkr\.ecr\.<REGION>\.amazonaws\.com/k8s-demo#${ECR_REPOSITORY}#" k8s/02-deployment.yaml k8s/01-replicaset-demo.yaml
```

## 5. Install the AWS Load Balancer Controller

Not scriptable blindly — it needs an IAM OIDC provider + IRSA role specific to your cluster. Follow the official steps: https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

## 6. Deploy the Kubernetes demo

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/02-deployment.yaml
kubectl apply -f k8s/03-service-clusterip.yaml
kubectl apply -f k8s/04-service-loadbalancer.yaml
kubectl apply -f k8s/05-ingress.yaml
kubectl get pods,svc,ingress -n k8s-demo -o wide
```

## 7. Demo commands

```bash
kubectl scale deployment k8s-demo -n k8s-demo --replicas=5
kubectl set env deployment/k8s-demo -n k8s-demo APP_VERSION=v2 && kubectl rollout status deployment/k8s-demo -n k8s-demo
kubectl rollout undo deployment/k8s-demo -n k8s-demo
kubectl apply -f k8s/01-replicaset-demo.yaml && kubectl scale rs k8s-demo-rs -n k8s-demo --replicas=5
```

## 8. Rebuild and re-sync the archive (whenever app/infra source changes, including before step 3)

```bash
cd ../../../IAC/Terraform/terraform-devops-labs/wind-client
powershell.exe -Command "& { \$stage='C:\prac\My-code\_project1-package'; \$archive='C:\prac\My-code\IAC\Terraform\terraform-devops-labs\wind-client\project1.zip'; if (Test-Path \$stage) { Remove-Item \$stage -Recurse -Force }; if (Test-Path \$archive) { Remove-Item \$archive -Force }; New-Item -ItemType Directory -Path \$stage | Out-Null; robocopy 'C:\prac\My-code\projects\project1' \"\$stage\project1\" /E /XD .terraform /XF terraform.tfstate terraform.tfstate.backup terraform.tfvars | Out-Null; Compress-Archive -Path \"\$stage\project1\" -DestinationPath \$archive -CompressionLevel Optimal; Remove-Item \$stage -Recurse -Force }"
aws s3 cp project1.zip "s3://$(terraform output -raw transfer_bucket_name)/project1.zip"
```

On the client:
```powershell
aws s3 cp s3://<transfer_bucket_name>/project1.zip C:\Users\Administrator\Downloads\project1.zip
Expand-Archive C:\Users\Administrator\Downloads\project1.zip -DestinationPath C:\work -Force
```

Browse to the NLB/ALB URL from step 6's output to verify the demo from the client.

## 9. Publish to GitHub

Run from `projects/project1` (this becomes the repo root — the `.gitignore` here already excludes `.terraform/`, `*.tfstate*`, `*.tfvars` (except `.example` files), and `*.zip`).

```bash
cd /c/prac/My-code/projects/project1
git init
git add -A
git status
```

**CHECKPOINT** — read the `git status` output carefully. Confirm `infra/terraform.tfvars` and any `.terraform/`/`*.tfstate*` files do **not** appear as staged (`.gitignore` should already exclude them). If any show up, stop and fix `.gitignore` before continuing — do not commit them.

```bash
git commit -m "Initial commit: Kubernetes feature demo on AWS EKS"
git branch -M main
```

Authenticate the GitHub CLI (one-time; opens a browser for login):

```bash
gh auth login
```

Create the GitHub repository and set it as the remote in one step:

```bash
gh repo create project1-k8s-eks-demo --public --source=. --remote=origin
```

Use `--private` instead of `--public` if you'd rather not make it public yet. Change the repo name if you prefer something else.

Push:

```bash
git push -u origin main
```

Verify on GitHub that `infra/terraform.tfvars`, any `.terraform/` directories, and any `*.tfstate*` files are **not** present in the pushed repo.

## 10. Cleanup (stop billing)

```bash
kubectl delete -f projects/project1/app/k8s
cd projects/project1/infra
terraform destroy
cd ../../../IAC/Terraform/terraform-devops-labs/wind-client
terraform destroy
```
