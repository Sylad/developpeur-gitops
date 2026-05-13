# developpeur-gitops

Manifests Helm + ArgoCD Applications pour les 5 apps perso :

- [`charts/ol-companion`](charts/ol-companion) — OL Companion (NestJS + React)
- [`charts/finance-tracker`](charts/finance-tracker) — *à venir*
- [`charts/warhammer40k`](charts/warhammer40k) — *à venir*
- [`charts/maritime-atlas`](charts/maritime-atlas) — *à venir, multi-service*

## Architecture

```
developpeur-gitops/
├── charts/                  # Helm charts par app
│   └── ol-companion/
│       ├── Chart.yaml
│       ├── values.yaml      # values preprod (k3s local Big-Blue)
│       └── templates/
│           ├── backend.yaml      # Deployment + Service + PVC NestJS
│           ├── frontend.yaml     # Deployment + Service nginx
│           └── ingress.yaml      # Ingress avec cert-manager
└── apps/                    # ArgoCD Application resources
    └── ol-companion.yaml    # Sync depuis charts/ol-companion
```

## Phases

| Phase | Cluster | Statut |
|---|---|---|
| Préprod | k3s local Big-Blue WSL2 | ✅ Active |
| Prod | Scaleway Kapsule | À venir |

## Workflow GitOps

1. Push d'un commit sur `main` →
2. ArgoCD détecte le drift (sync auto every 3min) →
3. Helm renderer applique les manifests dans le namespace `preprod` →
4. K8s reconcile l'état.

## Quick start (cluster local k3s)

```bash
# Bootstrap initial : créer l'Application ArgoCD
kubectl apply -f apps/ol-companion.yaml

# Vérifier la sync dans ArgoCD UI
open https://argocd.dev.local

# Forcer un re-sync manuel
argocd app sync ol-companion
```

## Secrets

Les secrets ne sont jamais commités en clair. Pattern à venir : SealedSecret
(Bitnami) → encryption avec la clé publique du controller dans le cluster,
décryption automatique côté cluster.

Pour la préprod actuelle, les secrets sont injectés manuellement via :
```bash
kubectl create secret generic ol-companion-secrets -n preprod \
  --from-env-file=/path/to/.env --dry-run=client -o yaml | kubectl apply -f -
```

## Refs

- [maritime-atlas/K8S-MIGRATION-ROADMAP.md](https://github.com/Sylad/maritime-atlas/blob/main/K8S-MIGRATION-ROADMAP.md) — plan détaillé 7 sprints
- ArgoCD : https://argocd.dev.local (cluster local)
- mkcert CA : `~/.local/share/mkcert/rootCA.pem`
