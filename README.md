# Kubernetes Feature Demo on AWS EKS

A small, forkable project that demonstrates the core building blocks of Kubernetes — Pods, ReplicaSets, Deployments, Services, and Ingress — end to end on a real AWS EKS cluster.

## What You'll See

A minimal Go app reports which pod served each request. Scale it, roll it, expose it via a Service/NLB and an Ingress/ALB, and watch traffic and rollouts happen in real time.

| Concept | Where |
|---|---|
| Pods, ReplicaSets, Deployments (scale, rolling update, rollback) | [app/k8s](app/k8s) |
| Services — ClusterIP and LoadBalancer (AWS NLB) | [app/k8s](app/k8s) |
| Ingress (AWS ALB) | [app/k8s/05-ingress.yaml](app/k8s/05-ingress.yaml) |
| The AWS infrastructure underneath (VPC, EKS, ECR) | [infra](infra) |

## Repository Layout

| Path | Contents |
|---|---|
| [infra/](infra/README.md) | Terraform: VPC, EKS cluster + node group, ECR repository, CodeBuild, LB controller IAM |
| [app/](app/README.md) | Go application, Dockerfile, and Kubernetes manifests |
| [project1.md](project1.md) | **Start here** — full end-to-end guide: about, components, how each layer is deployed, demo script, and a troubleshooting guide covering every real issue hit while building this |

## Quick Start

Read [project1.md](project1.md) first — it's the complete, single source of truth for this project: what it is, how to deploy the infrastructure/backend/Kubernetes layers, how to run the demo, and a troubleshooting guide with the exact problems (and fixes) encountered building it, including Free-Tier instance restrictions, ENI pod limits, and Windows zip-path bugs.

## Why This Is Useful to Fork

- No external dependencies in the app (Go standard library only) — easy to read in a few minutes.
- Clear, numbered Kubernetes manifests applied in order, each with a one-line comment on its purpose.
- Terraform is a self-contained, destroyable stack — no manual AWS Console clicking required.
- The troubleshooting guide in [project1.md](project1.md) documents real failures and fixes, not hypothetical ones — useful even if you don't use this exact project.
