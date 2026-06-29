#!/bin/bash

set -euxo pipefail

exec > >(tee /var/log/bootstrap.log)
exec 2>&1

echo "Bootstrap Started"

# packages...

echo "Installing Docker..."

curl -fsSL https://get.docker.com | sh

systemctl enable docker
systemctl start docker

echo "Docker Installed"

echo "Installing k3s..."

curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

until kubectl get nodes
do
    sleep 5
done

echo "k3s Ready"

mkdir -p /home/ubuntu/.kube

cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config

chown -R ubuntu:ubuntu /home/ubuntu/.kube

chmod 600 /home/ubuntu/.kube/config

echo "Kubeconfig copied"

echo "Installing Helm..."

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm version

echo "Helm Installed"

touch /var/log/bootstrap.finished

#create food , monitoring , argocd namespace

kubectl create namespace argocd

kubectl create namespace food

kubectl create namespace monitoring

#clone the github infra and apply ingress and rabbitmaq depl
cd /home/ubuntu
git clone https://github.com/beltawn3507/food_infra
kubectl apply -f /home/ubuntu/food_infra/infra/k8s

echo "applied infra files"

#argocd added

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl get all -n argocd
kubectl get svc -n argocd
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'


echo "Bootstrap Completed"
