#!/usr/bin/env bash
# upgrade-app.sh — bump le tag d'UN ou PLUSIEURS services dans values.yaml
# + commit + push. Le webhook ArgoCD sync Mini-Blue automatiquement (~2s).
#
# v2 (2026-05-22) : ciblé service par service. Avant, le script bumpait
# TOUTES les lignes 'tag:' du fichier, ce qui était incompatible avec la
# CI matrix-selective (seuls les services modifiés ont une image au new SHA).
# Cf memo feedback_upgrade_app_sh_bumps_all_pitfall.md.
#
# Usage :
#   ./scripts/upgrade-app.sh <chart> <service[,service2,...]> <new-tag>
#
# Exemples :
#   ./scripts/upgrade-app.sh maritime frontend sha-0c6cdbc
#   ./scripts/upgrade-app.sh maritime frontend,api sha-0c6cdbc
#
# Pré-requis :
#   - cwd = repo developpeur-gitops
#   - L'image doit déjà être présente en GHCR (CI passed pour le SHA).
#   - ArgoCD webhook GitHub configuré sur Mini-Blue (sync auto ~2s).

set -euo pipefail

CHART_NAME="${1:?Usage: upgrade-app.sh <chart> <service[,service2,...]> <new-tag>}"
SERVICES_CSV="${2:?Service(s) required (CSV: 'frontend' or 'frontend,api')}"
NEW_TAG="${3:?New tag required (ex: sha-0c6cdbc)}"

VALUES_FILE="charts/${CHART_NAME}/values.yaml"
[ ! -f "$VALUES_FILE" ] && { echo "❌ $VALUES_FILE introuvable"; exit 1; }

# Sanity check : prefix sha- si le tag ressemble à un SHA brut
if [[ "$NEW_TAG" =~ ^[0-9a-f]{7}$ ]]; then
  echo "⚠️  Tag '$NEW_TAG' ressemble à un SHA sans prefix. Convention CI = 'sha-${NEW_TAG}'."
  echo "    Si c'est volontaire (ex: tag latest, v1.2), continue. Sinon Ctrl+C et relance avec 'sha-${NEW_TAG}'."
  read -r -p "    Continuer avec '$NEW_TAG' ? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { echo "Annulé."; exit 1; }
fi

IFS=',' read -ra SERVICES <<< "$SERVICES_CSV"

echo "=== [1/3] Bump des tags ==="
CHANGED_LINES=0
for svc in "${SERVICES[@]}"; do
  svc=$(echo "$svc" | tr -d ' ')
  # Match le bloc YAML du service : de la ligne '  <svc>:' jusqu'à la
  # ligne '  <next-svc>:' (ou fin du bloc top-level). On limite la portée
  # du sed via une adresse range "/^  <svc>:/,/^  [a-z]/".
  # Le 'tag:' dans ce bloc a une indentation à 4 espaces ('    tag:').
  BEFORE=$(grep -nE "^    tag:\s*" "$VALUES_FILE" | awk -F: -v block_start="$(grep -nE "^  ${svc}:" "$VALUES_FILE" | head -1 | cut -d: -f1)" 'NR>0 && $1>=block_start { print; exit }' | head -1)
  if [ -z "$BEFORE" ]; then
    echo "  ⚠️  Service '$svc' : aucune ligne 'tag:' trouvée. Skip."
    continue
  fi

  # Range sed : du début du bloc service jusqu'à la prochaine clé top-level (`^  <x>:`).
  # On capture le tag actuel pour log.
  CURRENT_TAG=$(awk -v svc="^  ${svc}:" '
    $0 ~ svc { in_block=1; next }
    in_block && /^  [a-zA-Z]/ { exit }
    in_block && /^    tag:/ { sub(/^    tag:[ \t]*/, ""); print; exit }
  ' "$VALUES_FILE")

  if [ -z "$CURRENT_TAG" ]; then
    echo "  ⚠️  Service '$svc' : tag actuel introuvable. Skip."
    continue
  fi

  echo "  $svc : $CURRENT_TAG → $NEW_TAG"

  # Edit limité au bloc du service.
  sed -i "/^  ${svc}:/,/^  [a-zA-Z]/{s|^\(    tag:\s*\).*|\1${NEW_TAG}|}" "$VALUES_FILE"
  CHANGED_LINES=$((CHANGED_LINES + 1))
done

if [ $CHANGED_LINES -eq 0 ]; then
  echo "❌ Aucun service bumpé. Vérifier les noms : $SERVICES_CSV"
  exit 1
fi

# Sanity : vérifier que le diff ne touche pas plus de lignes que de services.
ACTUAL_CHANGES=$(git diff "$VALUES_FILE" | grep -cE '^[+-]\s+tag:\s*' || true)
EXPECTED_CHANGES=$((CHANGED_LINES * 2))  # 1 - et 1 + par ligne
if [ "$ACTUAL_CHANGES" -gt "$EXPECTED_CHANGES" ]; then
  echo "❌ Diff suspect : $ACTUAL_CHANGES lignes tag modifiées vs $EXPECTED_CHANGES attendues."
  echo "   Rollback :"
  git diff "$VALUES_FILE"
  git checkout "$VALUES_FILE"
  exit 1
fi

git diff --stat "$VALUES_FILE"

echo
echo "=== [2/3] Commit + push ==="
git add "$VALUES_FILE"
git commit -m "$(cat <<EOF
${CHART_NAME}: bump ${SERVICES_CSV} → ${NEW_TAG}

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push origin main

echo
echo "=== [3/3] Sync ArgoCD ==="
echo "✅ Push reçu par webhook GitHub. ArgoCD Mini-Blue sync auto en ~2s."
echo "   (Big-Blue ArgoCD scaled à 0 — cf argocd_single_cluster_decision_2026_05_19.md)"
echo
echo "Monitoring :"
echo "  # Bundle hash (frontend uniquement) :"
echo "  curl -sk https://aetherwx.sladoire.dev/globe | grep -oE 'styles-[A-Z0-9]+\\.css' | head -1"
echo
echo "  # Sur Mini-Blue :"
echo "  kubectl -n maritime get pods | grep -v Running"
echo "  kubectl -n argocd get app ${CHART_NAME} -o jsonpath='{.status.sync.status} | {.status.sync.revision}{\"\\n\"}'"
