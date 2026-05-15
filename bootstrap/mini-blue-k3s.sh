#!/usr/bin/env bash
# Bootstrap k3s + helm + mkcert + operators + ArgoCD sur Mini-Blue WSL2.
# Réutilise la recette Big-Blue validée nuit 13→14 mai 2026.
#
# Usage : ssh sylad@192.168.1.26 wsl bash < mini-blue-k3s.sh
# (ou exécuter directement dans WSL Mini-Blue : bash mini-blue-k3s.sh)
#
# Prérequis : WSL2 Ubuntu avec systemd activé (déjà OK Mini-Blue).
set -euo pipefail

echo "=== 1/8 — k3s install ==="
if ! command -v k3s >/dev/null 2>&1 ; then
  curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC="--disable=traefik --write-kubeconfig-mode=644" sh -
else
  echo "k3s déjà installé : $(k3s --version | head -1)"
fi

echo "=== 2/8 — kubeconfig user ==="
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config

echo "=== 3/8 — helm + mkcert ==="
if ! command -v helm >/dev/null 2>&1 ; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
fi
if ! command -v mkcert >/dev/null 2>&1 ; then
  sudo curl -fsSL "https://dl.filippo.io/mkcert/latest?for=linux/amd64" -o /usr/local/bin/mkcert
  sudo chmod +x /usr/local/bin/mkcert
  mkcert -install
fi

echo "=== 4/8 — namespaces ==="
kubectl create ns preprod --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns maritime --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns infra --dry-run=client -o yaml | kubectl apply -f -

echo "=== 5/8 — helm repos ==="
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets 2>/dev/null || true
helm repo add cnpg https://cloudnative-pg.github.io/charts 2>/dev/null || true
helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
helm repo update

echo "=== 6/8 — core infra (ingress-nginx hostNetwork + cert-manager + sealed-secrets) ==="
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n infra \
  --set controller.hostNetwork=true \
  --set controller.dnsPolicy=ClusterFirstWithHostNet \
  --set controller.service.type=ClusterIP \
  --set controller.kind=DaemonSet \
  --set controller.ingressClassResource.default=true \
  --wait --timeout 5m

helm upgrade --install cert-manager jetstack/cert-manager -n infra \
  --set crds.enabled=true --wait --timeout 5m

helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets -n infra \
  --wait --timeout 3m

# ClusterIssuer mkcert CA — créé après cert-manager.
kubectl create secret tls mkcert-ca -n infra \
  --cert="$HOME/.local/share/mkcert/rootCA.pem" \
  --key="$HOME/.local/share/mkcert/rootCA-key.pem" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'YAML' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: mkcert-ca-issuer
spec:
  ca:
    secretName: mkcert-ca
YAML

echo "=== 7/8 — operators (CNPG + RMQ + KEDA) ==="
helm upgrade --install cnpg cnpg/cloudnative-pg -n infra --wait --timeout 5m
helm upgrade --install keda kedacore/keda -n infra --wait --timeout 5m
kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml

echo "=== 8/8 — ArgoCD + bootstrap Application ==="
# Polling rapide (Sylvain 2026-05-15) : default 180s trop lent pour
# notre archi multi-cluster où le webhook GitHub ne notifie qu'un seul
# cluster (l'autre dépend du polling). 30s + jitter 10s = compromis
# réactivité / charge GitHub API. Big-Blue garde le webhook (sync ~2s),
# Mini-Blue sync via polling 30s.
helm upgrade --install argocd argo/argo-cd -n argocd \
  --set 'configs.params.server\.insecure=true' \
  --set server.ingress.enabled=true \
  --set server.ingress.ingressClassName=nginx \
  --set server.ingress.hostname=argocd.sladoire.dev \
  --set 'server.ingress.annotations.cert-manager\.io/cluster-issuer=mkcert-ca-issuer' \
  --set server.ingress.tls=true \
  --set controller.replicas=1 \
  --set applicationSet.replicas=1 \
  --set repoServer.replicas=1 \
  --set 'configs.cm.timeout\.reconciliation=30s' \
  --set 'configs.cm.timeout\.reconciliation\.jitter=10s' \
  --wait --timeout 10m

cat <<'YAML' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-bootstrap
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Sylad/developpeur-gitops.git
    targetRevision: main
    path: apps
    directory:
      recurse: false
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
YAML

echo ""
echo "============================================"
echo "Bootstrap Mini-Blue terminé."
echo ""
echo "Récupère le password ArgoCD admin :"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Étapes manuelles restantes :"
echo "  1. /etc/hosts WSL : ajouter '127.0.0.1 *.sladoire.dev' (ou /etc/hosts Windows)"
echo "  2. mkcert CA Windows : certutil -addstore -f ROOT \\\\wsl\$\\Ubuntu\\home\\sylad\\.local\\share\\mkcert\\rootCA.pem"
echo "  3. cloudflared tunnel : config dans charts/infra/cloudflared/"
echo "  4. Vraies images à importer dans k3s containerd :"
echo "       sudo k3s ctr images import /tmp/maritime-*.tar"
echo "============================================"
