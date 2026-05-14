# developpeur-gitops

Repo GitOps central pour les apps perso de Sylvain Ladoire. ArgoCD sync
ce repo vers les clusters K8s — toute modif passe par `git push`.

## Apps gérées

- [`charts/ol-companion`](charts/ol-companion) — OL Companion (NestJS + React)
- [`charts/finance-tracker`](charts/finance-tracker) — Finance Tracker (NestJS + React + PDF analyse Claude)
- [`charts/warhammer40k`](charts/warhammer40k) — Warhammer 40K codex (Angular 19 + NestJS)
- [`charts/maritime`](charts/maritime) — **AetherWX** (ex Maritime Atlas) services stateless
- [`charts/maritime-stateful`](charts/maritime-stateful) — AetherWX stateful (CNPG pg-catalog + pg-data + RMQ)
- [`charts/cloudflared`](charts/cloudflared) — Cloudflare Tunnel pour exposer `*.sladoire.dev`

## Clusters

| Cluster | Rôle | Allumage | Domaine |
|---|---|---|---|
| **Big-Blue WSL2** | Preprod / dev | Quand Sylvain code | `*.dev.local` |
| **Mini-Blue WSL2** | **Prod** 24/7 | Always-on (GEEKOM i9-13900HK 32GB) | `*.sladoire.dev` |

Préprod et prod sync les mêmes Helm charts via le pattern ArgoCD
app-of-apps. La distinction se fait via `values-prod.yaml` (à venir)
qui override images tag / replicas / ingress host pour la prod.

## Bootstrap d'un nouveau cluster

```bash
# Sur n'importe quel node WSL2 (Big-Blue ou Mini-Blue)
git clone https://github.com/Sylad/developpeur-gitops.git
cd developpeur-gitops
bash bootstrap/mini-blue-k3s.sh   # ou big-blue-k3s.sh quand disponible
```

Le script bootstrappe en 8 étapes :
1. k3s install
2. kubeconfig user
3. helm + mkcert
4. Namespaces (preprod, maritime, argocd, infra)
5. Helm repos
6. Core infra (ingress-nginx hostNetwork, cert-manager, sealed-secrets, ClusterIssuer mkcert)
7. Operators (CloudNativePG, KEDA, RabbitMQ Cluster Operator)
8. ArgoCD + Application `platform-bootstrap` qui sync tout `apps/*`

## Structure

```
developpeur-gitops/
├── apps/                       # ArgoCD Application manifests
│   ├── ol-companion.yaml
│   ├── finance-tracker.yaml
│   ├── warhammer40k.yaml
│   ├── maritime.yaml
│   ├── cloudflared.yaml
│   └── ...
├── bootstrap/                  # Scripts shell pour bootstrap cluster
│   └── mini-blue-k3s.sh
└── charts/                     # Helm charts
    ├── ol-companion/
    ├── finance-tracker/
    ├── warhammer40k/
    ├── maritime/
    ├── maritime-stateful/
    └── cloudflared/
```

## Workflow GitOps

1. Modifier un chart localement (`charts/<app>/values.yaml` ou template)
2. `git commit -m "..." && git push`
3. ArgoCD détecte le drift (sync auto every ~3 min)
4. Helm renderer applique les manifests vers le cluster
5. K8s reconcile (rolling update si image tag bump)

**Anti-pattern critique** : ne JAMAIS `kubectl patch` ou `helm upgrade --force`
direct sur un objet géré par ArgoCD avec `selfHeal: true`. Le revert
arrive dans 1-3 min vers la version Git.

## Secrets

Pas de secrets en clair dans Git. 2 patterns supportés :

- **Manuel via kubectl** (preprod, démarrage rapide) :
  ```bash
  kubectl create secret generic <name> -n <ns> \
    --from-env-file=/path/to/.env \
    --dry-run=client -o yaml | kubectl apply -f -
  ```

- **SealedSecrets (Bitnami)** pour la prod, chiffré dans Git :
  ```bash
  echo -n "value" | kubeseal --raw --namespace <ns> --name <name>
  ```

## Refs

- [maritime-atlas/K8S-MIGRATION-ROADMAP.md](https://github.com/Sylad/maritime-atlas/blob/main/K8S-MIGRATION-ROADMAP.md)
- [Case study migration nuit 13→14 mai 2026](https://claude-code-codex.pages.dev/case-studies/k8s-migration-overnight)
- ArgoCD UI Big-Blue : https://argocd.dev.local
- ArgoCD UI Mini-Blue (prod) : https://argocd.sladoire.dev (à venir)
