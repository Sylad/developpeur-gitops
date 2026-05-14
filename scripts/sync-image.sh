#!/usr/bin/env bash
# sync-image.sh — build local + export tar + SFTP Mini-Blue + import dans containerd des 2 clusters.
#
# Usage :
#   ./scripts/sync-image.sh <service-path> <image-name> <tag>
#
# Exemple :
#   ./scripts/sync-image.sh ~/projects/developpeur/maritime-atlas/services/api maritime-api v3-fix
#
# Pré-requis :
#   - Docker daemon local (WSL2 / Big-Blue)
#   - sudo passwordless OU on demandera le mdp pour `k3s ctr import` côté Big-Blue
#   - SSH sur Mini-Blue (host alias `mini-blue` ou IP 192.168.1.26) avec user `sylva`
#   - kubectl context pointant vers Big-Blue par défaut (peu importe, on ne touche pas K8s ici)
#
# Output :
#   - Tag image localement sur Big-Blue containerd
#   - Copie l'image sur Mini-Blue containerd
#   - L'utilisateur applique ensuite `scripts/upgrade-app.sh <chart> <tag>` pour bump dans Git.

set -euo pipefail

SERVICE_PATH="${1:?Usage: sync-image.sh <service-path> <image-name> <tag>}"
IMAGE_NAME="${2:?Image name required}"
TAG="${3:?Tag required}"

MINI_BLUE_HOST="${MINI_BLUE_HOST:-sylva@192.168.1.26}"
MINI_BLUE_WIN_PATH="${MINI_BLUE_WIN_PATH:-/Users/sylva}"

TAR_PATH="/tmp/${IMAGE_NAME}-${TAG}.tar"
REMOTE_TAR="${MINI_BLUE_WIN_PATH}/${IMAGE_NAME}-${TAG}.tar"

echo "=== [1/4] Build $IMAGE_NAME:$TAG depuis $SERVICE_PATH ==="
cd "$SERVICE_PATH"
docker build -t "$IMAGE_NAME:$TAG" .

echo
echo "=== [2/4] Export tar ($TAR_PATH) ==="
docker save "$IMAGE_NAME:$TAG" -o "$TAR_PATH"
ls -lh "$TAR_PATH"

echo
echo "=== [3/4] Import containerd Big-Blue (k3s namespace k8s.io) ==="
sudo k3s ctr -n k8s.io images import "$TAR_PATH"

echo
echo "=== [4/4] SFTP + import sur Mini-Blue ==="
echo "  → scp -O $TAR_PATH ${MINI_BLUE_HOST}:${REMOTE_TAR}"
scp -O "$TAR_PATH" "${MINI_BLUE_HOST}:${REMOTE_TAR}"

# Sur Mini-Blue : import via wsl bash (le user sudo passe par WSL)
echo "  → ssh ${MINI_BLUE_HOST} 'wsl sudo k3s ctr -n k8s.io images import /mnt/c${MINI_BLUE_WIN_PATH}/${IMAGE_NAME}-${TAG}.tar'"
ssh "${MINI_BLUE_HOST}" "wsl bash -c 'sudo k3s ctr -n k8s.io images import /mnt/c${MINI_BLUE_WIN_PATH}/${IMAGE_NAME}-${TAG}.tar'"

echo
echo "✅ $IMAGE_NAME:$TAG est dans containerd sur les 2 clusters."
echo
echo "Pour déployer (bump le tag dans Git + force ArgoCD sync) :"
echo "  ./scripts/upgrade-app.sh <chart-name> $TAG"
echo
echo "Cleanup tar local + remote (optionnel) :"
echo "  rm $TAR_PATH"
echo "  ssh ${MINI_BLUE_HOST} 'del C:${MINI_BLUE_WIN_PATH}/${IMAGE_NAME}-${TAG}.tar'"
