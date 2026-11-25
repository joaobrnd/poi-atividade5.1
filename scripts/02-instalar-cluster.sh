#!/usr/bin/env bash
# Instalacao do Docker, kubectl e Minikube - executar DENTRO da VM
set -euo pipefail

# 1. Docker (runtime usado pelo driver do Minikube)
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu
echo ">>> Saia e entre novamente no SSH para o grupo docker valer, depois siga."

# 2. kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# 3. Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64

# 4. Cluster.
#    --ports publica os NodePorts na interface da VM. Sem isso eles ficariam
#    acessiveis apenas na rede interna do container do Minikube (192.168.49.0/24)
#    e o Load Balancer do OpenStack nao conseguiria alcancar as aplicacoes.
#    O flag so tem efeito na CRIACAO do container: se o cluster ja existir,
#    rode "minikube delete" antes.
minikube start \
  --driver=docker \
  --cpus=3 \
  --memory=6144 \
  --ports=30001:30001 \
  --ports=30002:30002 \
  --ports=30003:30003

kubectl get nodes
docker port minikube
