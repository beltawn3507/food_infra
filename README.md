# food_infra

Infrastructure-as-Code and GitOps configuration for **Food**, a microservices-based food delivery platform. This repo provisions the cloud host, bootstraps a Kubernetes cluster, and continuously deploys every microservice via ArgoCD + Kustomize.

It does **not** contain application source code — each microservice (`auth`, `rest`, `rider`, `payment`, `realtime`, `client`) lives in its own repository and ships a container image to GHCR. This repo only holds the Kubernetes manifests, Kustomize overlays, ArgoCD Application definitions, and the Terraform/bootstrap scripts used to stand up the cluster.

## Architecture

```
                         ┌─────────────────────┐
                         │   Terraform (AWS)    │
                         │  EC2 + bootstrap.sh   │
                         └──────────┬───────────┘
                                    │ installs
                                    ▼
                     Docker → k3s → Helm → ArgoCD
                                    │
                                    ▼
                     ┌──────────────────────────┐
                     │        ArgoCD             │
                     │  (auto-sync per service)  │
                     └─────┬───────┬───────┬─────┘
                           │       │       │  ...
                           ▼       ▼       ▼
                     ┌────────┐┌────────┐┌────────┐
                     │  auth  ││  rest  ││ rider  │  ...
                     └────────┘└────────┘└────────┘
                              namespace: food

        Traefik Ingress (food-dev.duckdns.org, TLS via cert-manager)
                                    │
              ┌─────────────────────┴─────────────────────┐
              ▼                                            ▼
        client (static UI)                    /api/* routed to services
```

Traffic enters through a single Traefik `Ingress`, which path-routes requests to the appropriate backend service (auth, restaurant/cart/order, rider, payment, realtime/socket.io) and serves the frontend at `/`. RabbitMQ provides async messaging between services, Redis backs the `rest` service, and Prometheus scrapes `/metrics` from every backend for monitoring.

## Repository structure

```
food_infra/
├── argocd/                # ArgoCD Application manifests (one per microservice)
│   ├── argo-auth.yaml
│   ├── argo-rest.yaml
│   ├── argo-rider.yaml
│   ├── argo-payment.yaml
│   ├── argo-realtime.yaml
│   └── argo-client.yaml
├── auth/                  # Auth service — Deployment, Service, Kustomization
├── rest/                  # Restaurant/menu/cart/order service (+ Redis cache)
├── rider/                 # Rider service
├── payment/               # Payment & file-upload service
├── realtime/               # Realtime / Socket.IO service
├── client/                # Frontend (static) service
├── infra/
│   ├── k8s/                # Cluster-wide resources: Ingress, RabbitMQ
│   ├── monitoring/         # Prometheus scrape config
│   └── terraform/          # AWS EC2 provisioning + bootstrap script
└── .gitignore
```

Each service directory follows the same pattern: a `*-depl.yaml` (Deployment + Service) and a `kustomization.yaml` that pins the container image tag pulled from GHCR.

## Services

| Service    | Namespace | Port | Routed paths                                                          |
|------------|-----------|------|-------------------------------------------------------------------------|
| `client`   | food      | 80   | `/`                                                                     |
| `auth`     | food      | 5000 | `/api/auth`                                                             |
| `rest`     | food      | 5001 | `/api/restaurant`, `/api/item`, `/api/cart`, `/api/address`, `/api/order` |
| `payment`  | food      | 5002 | `/api/payment`, `/api/upload`                                           |
| `realtime` | food      | 5004 | `/api/v1/internal`, `/socket.io`                                        |
| `rider`    | food      | 5005 | `/api/rider`                                                             |

Supporting infrastructure: RabbitMQ (messaging), Redis (`rest` cache), Prometheus (metrics), cert-manager + Let's Encrypt (TLS), Traefik (ingress controller).

## How deployment works

1. **Provision** — `infra/terraform/ec2.tf` creates an AWS EC2 instance (`ap-south-1`), a security group allowing HTTP/SSH, an Elastic IP, and copies local secrets to the box over SSH.
2. **Bootstrap** — `infra/terraform/bootstrap.sh` runs on first boot and installs Docker, k3s, and Helm; creates the `food`, `argocd`, and `monitoring` namespaces; clones this repo and applies `infra/k8s` (Ingress + RabbitMQ); then installs ArgoCD and exposes it via a `NodePort`.
3. **GitOps sync** — Each manifest in `argocd/` is an ArgoCD `Application` pointing at this repo with `path: <service>`, `automated.prune`, and `selfHeal` enabled, so ArgoCD continuously reconciles the live cluster state with what's committed here.
4. **Image updates** — CI in each service's own repo builds and pushes an image to `ghcr.io/beltawn3507/food_<service>`; the corresponding `kustomization.yaml` here is updated with the new image tag (by commit SHA) to trigger a rollout.

## Prerequisites

- An AWS account and credentials configured for Terraform
- A domain (this setup uses `food-dev.duckdns.org` via DuckDNS) pointed at the instance's Elastic IP
- Kubernetes `Secret`s for each service (`auth-secret`, `rest-secret`, `payment-secret`, `rider-secret`, `realtime-secret`) created in the `food` namespace — these are **not** stored in this repo

## Getting started

```bash
# 1. Provision the host
cd infra/terraform
terraform init
terraform apply

# 2. SSH in and watch bootstrap finish
ssh -i new-key.pem ubuntu@<elastic-ip>
tail -f /var/log/bootstrap.log

# 3. Point ArgoCD at this repo (already wired via argocd/*.yaml)
kubectl apply -f argocd/

# 4. Create the per-service secrets before ArgoCD syncs successfully
kubectl -n food create secret generic auth-secret --from-env-file=./secret/auth.env
# ...repeat for rest, payment, rider, realtime
```

## Monitoring

`infra/monitoring/prom.yaml` configures Prometheus (deployed via the community Helm chart) to scrape Kubernetes API servers, nodes, pods/services with `prometheus.io/scrape` annotations, and each backend's `/metrics` endpoint directly by service DNS name.

## Notes

- Container images are pulled from GHCR (`ghcr.io/beltawn3507/food_*`); tags are pinned per environment via each `kustomization.yaml`.
- TLS is issued automatically by `cert-manager` using the `letsencrypt-prod` cluster issuer referenced in `infra/k8s/ingress.yaml`.
- This is a development/staging setup (single-node k3s, `duckdns.org` domain) rather than a production-hardened deployment.
