# Handoff session — 2026-05-14 matinée → après-midi

## État au moment du handoff (~9h45)

✅ **AetherWX preprod local Big-Blue fully UP** :
- 25 465 vessels visibles sur https://maritime.dev.local (WFS 200)
- Logo AetherWX 96px dans le panneau gauche map
- Hero About avec logo grand + credit ChatGPT
- Erreur LIVE compact (icône ⚠ + click-to-copy)
- Rebrand Couche 1 propagé (README, case-studies x2, About)
- 5 ArgoCD Applications Synced+Healthy
- Article k8s-migration-overnight publié sur claude-code-codex

✅ **Préparé en autonomie pendant ton absence** :
- `bootstrap/mini-blue-k3s.sh` — script 8 étapes pour cluster Mini-Blue
- `charts/cloudflared/` — Helm chart pour Cloudflare Tunnel
- `apps/cloudflared.yaml` — ArgoCD Application
- `charts/maritime/templates/ais-ingester.yaml` + values — ais-ingester K8s
- README gitops étoffé avec Mini-Blue + bootstrap flow

🟡 **En attente de toi (actions manuelles)** :

### 1. SSH access Mini-Blue (bloqué)

Dans `C:\Users\sylad\.ssh\authorized_keys` (côté Windows hôte, **pas WSL**) :

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOLUPYXb7KAuKzD4EOtIg0ieGKx0xp9Iw93F3+zQFiyv sylvain.ladoire@gmail.com
```

Crée le dossier si absent :
```powershell
mkdir C:\Users\sylad\.ssh
notepad C:\Users\sylad\.ssh\authorized_keys
```

Une fois fait, je SSH directement et lance le bootstrap k3s Mini-Blue.

### 2. Build + transfer images vers Mini-Blue

Quand SSH OK, je vais lancer côté Big-Blue (automatique) :
```bash
# Transfer les tars vers Mini-Blue
scp /tmp/maritime-*.tar /tmp/maritime-ais-ingester.tar sylad@192.168.1.26:/tmp/
# Puis ssh + sudo k3s ctr images import
```

### 3. Cloudflare Tunnel token

Dans Cloudflare Zero Trust → Networks → Tunnels :
1. Create tunnel "aetherwx-mini-blue"
2. Récupère le token (`eyJh...`)
3. Configure les Public Hostnames :
   - `aetherwx.sladoire.dev` → `http://maritime-frontend.maritime.svc.cluster.local:80`
   - `geoserver.sladoire.dev` → `http://geoserver.maritime.svc.cluster.local:8080`
   - `argocd.sladoire.dev` → `http://argocd-server.argocd.svc.cluster.local:80`
   - `ol.sladoire.dev` → `http://ol-frontend.preprod.svc.cluster.local:80`
   - `finance.sladoire.dev` → `http://finance-frontend.preprod.svc.cluster.local:80`
   - `warhammer.sladoire.dev` → `http://warhammer-frontend.preprod.svc.cluster.local:80`

Stocke le token via :
```bash
kubectl create secret generic cloudflared-token -n infra \
  --from-literal=token='<TOKEN>'
```

### 4. AISSTREAM API key

Pour ais-ingester en K8s, faut transférer la clé `AISSTREAM_API_KEY` qui
est dans ton `.env` local maritime-atlas. Pattern safe :
```bash
ssh nas "cat /volume2/docker/developpeur/maritime-atlas/.env" \
  | grep AISSTREAM > /tmp/aisstream.env
kubectl create secret generic ais-ingester-secrets -n maritime \
  --from-env-file=/tmp/aisstream.env \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/aisstream.env
```

### 5. Image ais-ingester à importer dans Big-Blue k3s

```bash
sudo k3s ctr images import /tmp/maritime-ais-ingester.tar
kubectl patch app maritime -n argocd --type merge \
  -p '{"operation":{"sync":{"revision":"main"}}}'
```

## Ordre d'exécution à ton retour

1. Étape 1 (SSH key Windows) — sans ça rien d'autre ne tourne pour Mini-Blue
2. Étape 5 (image ais-ingester Big-Blue) — déclenche le flux AIS live preprod
3. Étape 4 (Secret AISSTREAM côté Big-Blue) — sans la clé ais-ingester ne marche pas
4. Étape 3 (Cloudflare tunnel) — peut se faire pendant que k3s Mini-Blue boot
5. Étape 2 (transfer images Mini-Blue) — quand Mini-Blue cluster up

Total temps estimé : ~45 min de toi + 1h en parallèle d'opérations cluster.

## Décisions encore en attente

- Repo GitHub rename `maritime-atlas` → `aetherwx` (Couche 3, irréversible URLs)
- Dossier local `/projects/developpeur/maritime-atlas/` → `/projects/developpeur/aetherwx/`
- App Android AetherWX (Expo) — weekend MVP
