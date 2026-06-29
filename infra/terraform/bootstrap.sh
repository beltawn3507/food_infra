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

#k3s

echo "Installing k3s..."

curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

until kubectl get nodes
do
    sleep 5
done

echo "k3s Ready"

#kubectl installation

mkdir -p /home/ubuntu/.kube

cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config

chown -R ubuntu:ubuntu /home/ubuntu/.kube

chmod 600 /home/ubuntu/.kube/config

echo "Kubeconfig copied"

#helm 

echo "Installing Helm..."

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm version

echo "Helm Installed"

touch /var/log/bootstrap.finished

echo "Bootstrap Completed"
