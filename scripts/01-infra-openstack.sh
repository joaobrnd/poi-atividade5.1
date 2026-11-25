#!/usr/bin/env bash
# Provisionamento da infraestrutura na cloud OpenStack do LSD - Grupo 15
# Executar na maquina local, com o arquivo RC carregado:
#   source Provisionamento-openrc.sh
set -euo pipefail

SUBNET_PROVIDER="17de9c72-e5dc-4da0-ae0a-013f7e42400e"
SG="security-group-grupo-15"
VM="vm-k8s-grupo-15"
KEY="poi-k8s-grupo15"

# 1. Par de chaves para acesso SSH a VM
openstack keypair create --private-key ~/poi-k8s.pem "$KEY"
chmod 600 ~/poi-k8s.pem

# 2. VM: 4 vCPUs e 8 GB de RAM (general.large), Ubuntu 24.04 LTS
openstack server create \
  --flavor general.large \
  --image ubuntu-24.04 \
  --key-name "$KEY" \
  --network provider \
  "$VM"

openstack server show "$VM" -c id -c status -c addresses
VM_IP=$(openstack server show "$VM" -f value -c addresses | sed 's/.*provider=//' | cut -d, -f1)
echo "IP da VM: $VM_IP"

# 3. Portas dos NodePorts do Kubernetes no grupo de seguranca
for port in 30001 30002 30003; do
  openstack security group rule create --proto tcp --dst-port "$port" "$SG"
done
openstack server add security group "$VM" "$SG"

# 4. Load Balancer: apontar os pools existentes para a VM nova.
#    SSH (porta externa 2015) -> 22 na VM
#    Aplicacoes (15801/15802/15803) -> NodePorts 30001/30002/30003
repontar () {
  local pool=$1 porta=$2
  local mid
  mid=$(openstack loadbalancer member list "$pool" -f value -c id || true)
  [ -n "$mid" ] && openstack loadbalancer member delete "$pool" "$mid"
  while [ "$(openstack loadbalancer pool show "$pool" -f value -c provisioning_status)" != "ACTIVE" ]; do
    sleep 5
  done
  openstack loadbalancer member create \
    --subnet-id "$SUBNET_PROVIDER" \
    --address "$VM_IP" \
    --protocol-port "$porta" \
    --wait "$pool"
}

repontar ssh-pool-grupo-15     22
repontar cpu-pool-grupo-15     30001
repontar memory-pool-grupo-15  30002
repontar io-pool-grupo-15      30003
