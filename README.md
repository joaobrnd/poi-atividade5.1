# Atividade 5 — Kubernetes na Cloud do LSD (Grupo 15)

Deploy das três aplicações da disciplina em um cluster Kubernetes instalado com
Minikube, sobre uma VM da cloud OpenStack do LSD, com acesso externo pelo Load
Balancer `poi-atividades`.

| Item | Valor |
|---|---|
| VM | `vm-k8s-grupo-15` |
| ID da VM | `c1f14657-2b92-4304-815e-07f9916b84bb` |
| IP interno da VM | `10.5.11.59` |
| Flavor | `general.large` — 4 vCPUs, 8 GB RAM, 20 GB disco |
| Sistema operacional | Ubuntu Server 24.04.3 LTS |
| Kubernetes | v1.37.0 (Minikube v1.39.0, driver `docker`, containerd 2.3.4) |
| IP público do Load Balancer | `150.165.85.77` |

URLs das aplicações em execução:

| Aplicação | URL | NodePort | Porta no pod |
|---|---|---|---|
| `cpu_service` | http://150.165.85.77:15801/docs | 30001 | 8001 |
| `memory_service` | http://150.165.85.77:15802/docs | 30002 | 8002 |
| `io_service` | http://150.165.85.77:15803/docs | 30003 | 8003 |

Acesso SSH à VM: `ssh -i poi-k8s.pem ubuntu@150.165.85.77 -p 2015`

## Arquitetura

```
Internet
   |
   v
Load Balancer poi-atividades  (IP público 150.165.85.77)
   |  listener 15801 -> cpu-pool-grupo-15     -> 10.5.11.59:30001
   |  listener 15802 -> memory-pool-grupo-15  -> 10.5.11.59:30002
   |  listener 15803 -> io-pool-grupo-15      -> 10.5.11.59:30003
   |  listener  2015 -> ssh-pool-grupo-15     -> 10.5.11.59:22
   v
VM vm-k8s-grupo-15  (10.5.11.59, Ubuntu 24.04, 4 vCPU / 8 GB)
   |  portas 30001-30003 publicadas pelo container do Minikube
   v
Cluster Kubernetes (Minikube, driver docker)
   namespace poi
   |  Service NodePort cpu-service     30001 -> Deployment  cpu-service    (2 réplicas)
   |  Service NodePort memory-service  30002 -> Deployment  memory-service (1 réplica)
   |  Service NodePort io-service      30003 -> StatefulSet io-service     (1 réplica + PVC 1Gi)
```

## 1. Infraestrutura no OpenStack

Script: [`scripts/01-infra-openstack.sh`](scripts/01-infra-openstack.sh)

A VM usa o flavor `general.large`, o menor que atende aos mínimos do enunciado
(4 vCPUs e 8 GB de RAM), com a imagem `ubuntu-24.04`.

O par de chaves `poi-k8s-grupo15` foi criado especificamente para esta atividade.
A chave privada fica apenas com o grupo; o OpenStack guarda só a pública, que é
injetada na VM pelo `cloud-init` no momento do provisionamento.

O grupo de segurança `security-group-grupo-15`, reaproveitado das atividades
anteriores, recebeu três regras novas de entrada (TCP 30001, 30002 e 30003) para
os NodePorts do cluster.

### Load Balancer

O balanceador `poi-atividades` é compartilhado pela turma, então cada grupo usa
portas externas próprias. Os *listeners* e *pools* do grupo 15 já existiam das
atividades anteriores e foram mantidos; o que mudou foram os **membros**, que
antes apontavam para a VM antiga nas portas das aplicações e agora apontam para
a VM nova nos NodePorts:

| Pool | Antes | Agora |
|---|---|---|
| `ssh-pool-grupo-15` | 10.5.10.123:22 | 10.5.11.59:22 |
| `cpu-pool-grupo-15` | 10.5.10.123:8001 | 10.5.11.59:30001 |
| `memory-pool-grupo-15` | 10.5.10.123:8002 | 10.5.11.59:30002 |
| `io-pool-grupo-15` | 10.5.10.123:8003 | 10.5.11.59:30003 |

Os *health monitors* dos pools fazem `GET /health` e não precisaram de ajuste:
o mesmo caminho responde através do NodePort.

Um detalhe operacional: o Octavia rejeita duas operações simultâneas no mesmo
pool (`HTTP 409 — pool is immutable`). O script espera o `provisioning_status`
voltar a `ACTIVE` entre a remoção do membro antigo e a criação do novo.

## 2. Cluster Kubernetes

Script: [`scripts/02-instalar-cluster.sh`](scripts/02-instalar-cluster.sh)

O cluster foi criado com:

```
minikube start --driver=docker --cpus=3 --memory=6144 \
  --ports=30001:30001 --ports=30002:30002 --ports=30003:30003
```

**Por que 3 vCPUs e 6 GB, e não os 4 e 8 da VM.** O requisito do enunciado é
sobre a máquina virtual, que atende integralmente. Deixar 1 vCPU e 2 GB fora do
cluster evita que o kubelet e os pods disputem CPU com o `sshd` e o restante do
sistema operacional, o que tornaria a própria VM difícil de administrar sob
carga.

**Por que `--ports` é indispensável.** Com o driver `docker`, o nó do Kubernetes
é um container e os NodePorts ficam na rede interna do Docker
(`192.168.49.0/24`), inalcançável de fora da VM. O flag `--ports` publica essas
portas na interface da VM (`0.0.0.0:30001-30003`), que é o que permite ao Load
Balancer do OpenStack entregar tráfego às aplicações. Verificação:

```
$ docker port minikube
30001/tcp -> 0.0.0.0:30001
30002/tcp -> 0.0.0.0:30002
30003/tcp -> 0.0.0.0:30003
```

O flag só tem efeito na **criação** do container do Minikube. Se o cluster já
existir, é preciso `minikube delete` antes — caso contrário ele é ignorado em
silêncio e nada fica acessível de fora.

Os addons `storage-provisioner` e `default-storageclass` são habilitados pelo
Minikube na subida e atendem o PVC do `io_service`.

## 3. Deploy das aplicações

Script: [`scripts/03-deploy.sh`](scripts/03-deploy.sh) · Manifestos: [`k8s/`](k8s/)

As imagens são as publicadas na atividade anterior, no Docker Hub:

- `stefaneguedes/poi-cpu-service:1.0.0`
- `stefaneguedes/poi-memory-service:1.0.0`
- `stefaneguedes/poi-io-service:1.0.0`

Tudo vive no namespace `poi`, isolando os recursos do grupo.

### Justificativa dos workloads

**`cpu_service` — Deployment com 2 réplicas.** O serviço é stateless: cada
requisição a `/recommend` é independente, e o cache de catálogo é apenas uma
otimização local, não estado compartilhado. Isso permite escalar
horizontalmente, e o Service distribui as requisições entre os pods. O limite de
1 vCPU por pod impede que um pedido pesado monopolize o nó.

**`memory_service` — Deployment com 1 réplica e estratégia `Recreate`.** O
serviço mantém um único buffer residente em memória. Com mais de uma réplica,
cada pod alocaria o seu próprio buffer — o dobro de RAM para o mesmo resultado —
e `/cache/status` responderia valores diferentes conforme o pod que atendesse,
quebrando a semântica do serviço. A estratégia `Recreate`, em lugar do
`RollingUpdate` padrão, garante que o pod antigo seja encerrado antes do novo
subir; sem isso, durante uma atualização dois pods coexistiriam alocando 1 GB
cada. O limite de 1536Mi corresponde ao `MEMORY_MAX_MB=1024` mais a folga do
interpretador.

**`io_service` — StatefulSet com 1 réplica e `volumeClaimTemplate` de 1Gi.** É o
único serviço com estado em disco: grava documentos e depois os lê e remove por
ID. Se o pod reiniciasse com um volume vazio, os IDs já devolvidos aos clientes
deixariam de existir. O StatefulSet dá ao pod identidade estável e um PVC próprio
e persistente — exatamente a diferença em relação a um Deployment, cujo
armazenamento é intercambiável entre réplicas. A variável `IO_DATA_DIR=/data`
aponta o serviço para o volume montado.

Os três têm `readinessProbe` e `livenessProbe` em `/health`: a primeira evita que
o Service mande tráfego para um pod que ainda está subindo, a segunda reinicia o
pod se ele travar.

### Exposição externa

Os três Services são do tipo **NodePort**, com portas fixas (30001, 30002,
30003) em vez de alocadas automaticamente. Portas fixas são necessárias aqui
porque os membros do Load Balancer do OpenStack são configurados manualmente e
precisam de um destino estável.

O `io_service` tem dois Services: o headless `io-service-headless`, exigido pelo
StatefulSet para dar identidade de rede ao pod, e o `io-service` NodePort, usado
para o acesso externo.

## 4. Verificação

De dentro da VM, nos NodePorts publicados:

```
$ curl localhost:30001/health
{"status":"ok","service":"cpu-recommendation"}
$ curl localhost:30002/health
{"status":"ok","service":"memory-catalog"}
$ curl localhost:30003/health
{"status":"ok","service":"io-document"}
```

De qualquer máquina, pelo IP público do Load Balancer:

```
$ curl http://150.165.85.77:15801/health
{"status":"ok","service":"cpu-recommendation"}
$ curl http://150.165.85.77:15802/health
{"status":"ok","service":"memory-catalog"}
$ curl http://150.165.85.77:15803/health
{"status":"ok","service":"io-document"}
```

Cada aplicação também publica a documentação interativa do FastAPI em `/docs`.
A raiz (`/`) devolve `{"detail":"Not Found"}`, porque os serviços não definem
rota em `/` — é resposta da aplicação, não falha de acesso.

## 5. Limpeza da infraestrutura anterior

Depois de o cluster entrar em operação, os recursos da atividade anterior foram
removidos:

```
openstack server delete vm-grupo-15
openstack volume delete volume-grupo-15
```

Os *listeners* e *pools* foram mantidos de propósito: são do grupo, já estavam
com as portas externas reservadas no balanceador compartilhado, e recriá-los
traria risco de conflito de porta com outros grupos.

## Estrutura do repositório

```
k8s/
  00-namespace.yaml      namespace poi
  10-cpu-service.yaml    Deployment (2 réplicas) + Service NodePort 30001
  20-memory-service.yaml Deployment (1 réplica, Recreate) + Service NodePort 30002
  30-io-service.yaml     Service headless + StatefulSet + PVC + Service NodePort 30003
scripts/
  01-infra-openstack.sh  VM, chave, grupo de segurança e Load Balancer
  02-instalar-cluster.sh Docker, kubectl, Minikube e subida do cluster
  03-deploy.sh           kubectl apply e verificação
```
