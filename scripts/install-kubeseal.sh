#!/usr/bin/env bash
# install-kubeseal.sh — installe kubeseal CLI sur Big-Blue WSL2.
#
# Permet de scelle un Secret K8s en SealedSecret chiffré avec la clé
# publique du controller sealed-secrets (déjà déployé dans ns infra).
# Le SealedSecret peut alors être commité en clair dans Git, ArgoCD
# le déploie sur chaque cluster, et le controller le déchiffre
# au moment du déploiement.

set -euo pipefail

KUBESEAL_VERSION="${KUBESEAL_VERSION:-0.26.3}"

if command -v kubeseal &>/dev/null; then
  echo "kubeseal déjà installé : $(kubeseal --version 2>&1 | head -1)"
  exit 0
fi

echo "=== Téléchargement kubeseal $KUBESEAL_VERSION ==="
cd /tmp
curl -sL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" -o kubeseal.tar.gz
tar -xzf kubeseal.tar.gz kubeseal

echo "=== Move /usr/local/bin/ (sudo) ==="
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
rm kubeseal kubeseal.tar.gz

echo "=== Vérif ==="
kubeseal --version

echo
echo "Test fetch cert depuis controller sealed-secrets :"
kubeseal --fetch-cert --controller-namespace=infra --controller-name=sealed-secrets | head -3
echo "..."

echo
echo "✅ kubeseal installé."
echo
echo "Usage type :"
echo "  # 1) Créer un Secret K8s en mémoire (jamais persisté)"
echo "  kubectl create secret generic mon-secret -n preprod \\"
echo "    --from-literal=KEY=value \\"
echo "    --dry-run=client -o yaml > /tmp/secret.yaml"
echo "  # 2) Scelle-le avec la clé publique du controller"
echo "  kubeseal --controller-namespace=infra --controller-name=sealed-secrets \\"
echo "    -f /tmp/secret.yaml -o yaml > charts/mon-app/templates/sealed-secret.yaml"
echo "  rm /tmp/secret.yaml"
echo "  # 3) Commit + push : ArgoCD applique le SealedSecret → controller déchiffre"
