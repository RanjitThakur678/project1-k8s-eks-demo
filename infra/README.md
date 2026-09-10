# Infrastructure: EKS Foundation (Terraform)

Terraform stack that provisions the AWS foundation the [application](../app/README.md) runs on: a VPC, an EKS cluster with a managed node group, and an ECR repository for the container image.

## What This Creates

| Resource | Purpose |
|---|---|
| VPC (2 AZs, public + private subnets, 1 NAT gateway) | Network foundation; worker nodes stay in private subnets |
| EKS cluster + managed node group | Runs the [demo Kubernetes workload](../app/README.md) |
| ECR repository (image scan on push) | Stores the built application container image |

Public/private subnets are tagged (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`, `kubernetes.io/cluster/<name>=shared`) so the AWS Load Balancer Controller can auto-discover them for the NLB Service and ALB Ingress used by the app.

## Variables

| Name | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region for all infrastructure |
| `project_name` | `k8s-feature-demo` | Prefix used to name resources |
| `environment` | `dev` | Environment label |
| `kubernetes_version` | `1.31` | EKS control plane version |
| `node_instance_types` | `["t3.medium"]` | EC2 instance types for the node group |
| `node_desired_size` / `node_min_size` / `node_max_size` | `2` / `2` / `3` | Node group scaling bounds |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | CIDRs allowed to reach the public EKS API endpoint — **restrict this** to your jump host/office IP |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | EKS cluster name |
| `aws_region` | Region used for this deployment |
| `cluster_endpoint` | EKS API server endpoint |
| `ecr_repository_url` | ECR repository URL to push the app image to |
| `configure_kubectl` | Ready-to-run `aws eks update-kubeconfig` command |

## Usage

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars - at minimum restrict cluster_endpoint_public_access_cidrs

terraform init
terraform plan
terraform apply
```

```powershell
aws eks update-kubeconfig --region (terraform output -raw aws_region) --name (terraform output -raw cluster_name)
```

## Destroy

```powershell
terraform destroy
```

Destroy promptly after each session — the EKS control plane, EC2 nodes, and NAT gateway bill continuously. Delete any Kubernetes `Service`/`Ingress` objects that provisioned an NLB/ALB *before* destroying, otherwise Terraform can hang or fail to remove the VPC.

## Security Notes

- `cluster_endpoint_public_access_cidrs` defaults to open (`0.0.0.0/0`) for demo convenience — restrict it before anything beyond a short-lived lab.
- Worker nodes run only in private subnets; a single NAT gateway provides outbound internet access (fine for a demo — use one NAT gateway per AZ for production HA).
- ECR image scanning is enabled on push.

## Full Walkthrough

See the [project runbook](../project1.md) for the complete path: Windows jump host setup, image build/push, and applying the Kubernetes manifests on top of this infrastructure.
