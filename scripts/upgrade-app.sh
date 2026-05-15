#!/usr/bin/env bash
# upgrade-app.sh — bump le tag image dans values.yaml + commit + push + force ArgoCD sync.
#
# Usage :
#   ./scripts/upgrade-app.sh <chart-name> <new-tag>
#
# Exemple :
#   ./scripts/upgrade-app.sh maritime v3-fix
#
# L'image cible doit déjà être présente dans containerd des 2 clusters (cf sync-image.sh).
#
# Pré-requis :
#   - cwd = repo developpeur-gitops
#   - kubectl context = Big-Blue (force-refresh ArgoCD)
#   - SSH config OK pour mini-blue (la sync ArgoCD côté Mini-Blue est faite via SSH)

set -euo pipefail

CHART_NAME="${1:?Usage: upgrade-app.sh <chart-name> <new-tag>}"
NEW_TAG="${2:?New tag required}"

VALUES_FILE="charts/${CHART_NAME}/values.yaml"
[ ! -f "$VALUES_FILE" ] && { echo "❌ $VALUES_FILE introuvable"; exit 1; }

echo "=== [1/4] Détection du chemin tag actuel dans $VALUES_FILE ==="
# Cherche la ligne 'tag: vX' la plus probable (sous une clé image:)
CURRENT_LINE=$(grep -nE '^\s*tag:\s*' "$VALUES_FILE" | head -1)
[ -z "$CURRENT_LINE" ] && { echo "❌ Pas de 'tag:' trouvé dans $VALUES_FILE"; exit 1; }
LINE_NUM=$(echo "$CURRENT_LINE" | cut -d: -f1)
CURRENT_TAG=$(echo "$CURRENT_LINE" | sed 's/^\s*tag:\s*//')
echo "  Ligne $LINE_NUM : tag: $CURRENT_TAG → $NEW_TAG"

echo
echo "=== [2/4] Update + commit + push ==="
sed -i "s|^\(\s*tag:\s*\).*|\1${NEW_TAG}|" "$VALUES_FILE"
git diff --stat "$VALUES_FILE"
git add "$VALUES_FILE"
git commit -m "$(cat <<EOF
${CHART_NAME} : bump tag ${CURRENT_TAG} → ${NEW_TAG}

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main

echo
echo "=== [3/4] Force ArgoCD refresh Big-Blue ==="
kubectl annotate application "$CHART_NAME" -n argocd argocd.argoproj.io/refresh=hard --overwrite

echo
echo "=== [4/4] Force ArgoCD refresh Mini-Blue (via SSH WSL) ==="
ssh "${MINI_BLUE_HOST:-sylad@192.168.1.26}" "wsl bash -c 'kubectl annotate application ${CHART_NAME} -n argocd argocd.argoproj.io/refresh=hard --overwrite'" || \
  echo "⚠️ Refresh Mini-Blue failed (vérifier connexion SSH)"

echo
echo "✅ ${CHART_NAME}:${NEW_TAG} déployé. Les pods vont se recréer dans les 30s sur les 2 clusters."
echo
echo "Pour suivre :"
echo "  kubectl get pods -n <namespace> -l app=<your-app> -w"
echo "  kubectl get application -n argocd ${CHART_NAME}"
