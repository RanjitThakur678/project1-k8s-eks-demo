# Application: Kubernetes Feature Demo

A tiny Go service (API + static frontend, one binary, one container) built to make core Kubernetes concepts visible and clickable on a real AWS EKS cluster.

## What This Demonstrates

| Kubernetes concept | Manifest | How you see it |
|---|---|---|
| Pods | any | `kubectl get pods -o wide` shows each pod's node/IP |
| ReplicaSet | [k8s/01-replicaset-demo.yaml](k8s/01-replicaset-demo.yaml) | Standalone ReplicaSet, isolated from Services, to inspect `kubectl get rs` behavior on its own |
| Deployment (scaling, rolling update, rollback) | [k8s/02-deployment.yaml](k8s/02-deployment.yaml) | `kubectl scale`, `kubectl rollout status/undo` |
| Service (ClusterIP) | [k8s/03-service-clusterip.yaml](k8s/03-service-clusterip.yaml) | Stable in-cluster endpoint used by the Ingress |
| Service (LoadBalancer / AWS NLB) | [k8s/04-service-loadbalancer.yaml](k8s/04-service-loadbalancer.yaml) | Public NLB hostname load-balancing straight to pods |
| Ingress (AWS ALB) | [k8s/05-ingress.yaml](k8s/05-ingress.yaml) | Public ALB hostname routing HTTP to the ClusterIP Service |

The API endpoint `/api/info` returns the serving pod's name, IP, node, and a per-pod request counter — refresh the page repeatedly (or hit the Service/Ingress URL in a loop) and watch traffic spread across replicas.

## Folder Layout

```
backend/
  main.go        Go API + static file server
  go.mod
  Dockerfile      Multi-stage build -> distroless runtime image
  static/         Frontend (plain HTML/JS, no build step)
k8s/               Kubernetes manifests, apply in numeric order
  00-namespace.yaml
  01-replicaset-demo.yaml
  02-deployment.yaml
  03-service-clusterip.yaml
  04-service-loadbalancer.yaml
  05-ingress.yaml
```

## Run Locally (no Kubernetes needed)

```powershell
cd backend
go run main.go
```

Visit `http://localhost:8080`. Useful for verifying the app itself before touching Kubernetes.

## Deploy to EKS

This app is deployed onto infrastructure created by [../infra](../infra) (VPC, EKS, ECR). For the full step-by-step path — including the disposable Windows jump host, image build/push, and every `kubectl` command for each feature above — see the [project runbook](../project1.md).

Quick reference once the image is built and pushed to the ECR repository from `../infra`'s output:

```powershell
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/02-deployment.yaml
kubectl apply -f k8s/03-service-clusterip.yaml
kubectl apply -f k8s/04-service-loadbalancer.yaml
kubectl apply -f k8s/05-ingress.yaml
```

`k8s/01-replicaset-demo.yaml` is applied separately (see the runbook) — it's a teaching-only standalone ReplicaSet, not part of the normal rollout.

## Notes for Forking

- Swap the container registry and image tag in `02-deployment.yaml` / `01-replicaset-demo.yaml` to point at your own ECR repository.
- The app has no external dependencies (standard library only) — safe to read end-to-end in a few minutes.
- Health checks (`/healthz`) back the Deployment's readiness/liveness probes.
