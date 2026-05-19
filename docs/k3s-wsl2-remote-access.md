# Accès distant à un cluster k3s WSL2 depuis un autre PC

> Recette validée 2026-05-19 lors du sprint Satellites pour donner accès kubectl
> à Claude (sur Big-Blue) vers le cluster prod Mini-Blue (192.168.1.26). Avant
> ça, copy-paste manuel à chaque diag → ROI infini une fois en place.

## Contexte

* Machine cible (serveur k3s) : Windows + WSL2 Ubuntu + k3s — ici **Mini-Blue 192.168.1.26**
* Machine cliente (kubectl distant) : autre PC Linux — ici **Big-Blue** (WSL Ubuntu)
* Objectif : utiliser `kubectl` à distance, sans SSH ni copy-paste

---

## 1. Vérifier le cluster k3s localement

Sur le Windows hébergeant WSL :

```powershell
wsl -d Ubuntu -- sudo kubectl get nodes
```

Doit répondre :

```text
mini-blue   Ready   control-plane
```

## 2. Vérifier que k3s écoute sur 6443

```powershell
wsl -d Ubuntu -- sudo ss -lntp | findstr 6443
```

Doit montrer `*:6443`.

## 3. Créer le portproxy Windows

PowerShell admin :

```powershell
netsh interface portproxy add v4tov4 `
  listenaddress=0.0.0.0 `
  listenport=6443 `
  connectaddress=172.28.102.52 `
  connectport=6443
```

⚠️ `172.28.102.52` = IP WSL obtenue avec :

```powershell
wsl hostname -I
```

⚠️ Prendre **UNIQUEMENT la première IP**.

## 4. Vérifier le portproxy

```powershell
netsh interface portproxy show all
```

Résultat attendu :

```text
0.0.0.0   6443   172.28.102.52   6443
```

## 5. Ouvrir le firewall Windows

```powershell
New-NetFirewallRule `
  -DisplayName "Kubernetes API 6443" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 6443 `
  -Action Allow
```

## 6. Tester l'API Kubernetes depuis un autre PC

Depuis Big-Blue :

```bash
curl -k https://192.168.1.26:6443/version
```

Réponse attendue :

```json
{"status":"Failure","message":"Unauthorized"}
```

⚠️ C'est **NORMAL**. Ça prouve que l'API est joignable (l'unauthorized vient
du fait qu'on n'envoie pas de cert client).

## 7. Exporter le kubeconfig depuis Mini-Blue

Sur le Windows cible :

```powershell
wsl -d Ubuntu -- sudo k3s kubectl config view --raw
```

Copier le résultat complet.

## 8. Créer le kubeconfig sur Big-Blue

```bash
mkdir -p ~/.kube
nano ~/.kube/mini-blue.yaml
```

Coller le contenu.

## 9. Modifier l'adresse du serveur

Dans le fichier, remplacer :

```yaml
server: https://127.0.0.1:6443
```

par :

```yaml
server: https://192.168.1.26:6443
```

## 10. Désactiver temporairement la vérification TLS

Le certificat k3s WSL ne contient pas l'IP LAN Windows par défaut.

```bash
kubectl --kubeconfig ~/.kube/mini-blue.yaml \
  config set-cluster default \
  --insecure-skip-tls-verify=true
```

> **Alternative propre (sans TLS bypass)** : ajouter `tls-server-name: 127.0.0.1`
> dans le bloc `cluster:` du kubeconfig — kubectl envoie SNI=127.0.0.1
> (qui EST dans le cert SAN) tout en connectant à 192.168.1.26. La
> validation TLS est préservée. C'est ce qu'on a utilisé 2026-05-19.

## 11. Tester kubectl distant

```bash
kubectl --kubeconfig ~/.kube/mini-blue.yaml get nodes
```

Résultat attendu :

```text
mini-blue   Ready   control-plane
```

## 12. Alias pratique

```bash
alias kmini='kubectl --kubeconfig ~/.kube/mini-blue.yaml'
```

Puis :

```bash
kmini get pods -A
```

---

## Solution propre long terme (TLS — éviter le bypass)

Éditer côté Mini-Blue :

```bash
sudo nano /etc/rancher/k3s/config.yaml
```

Ajouter :

```yaml
tls-san:
  - 192.168.1.26
```

Puis redémarrer k3s pour régénérer un certificat valide pour l'IP LAN :

```bash
sudo systemctl restart k3s
```

La verif TLS deviendra propre sans `insecure-skip-tls-verify` ni
`tls-server-name` workaround.

---

## Troubleshooting rapide

| Symptôme | Cause probable | Fix |
|---|---|---|
| `dial tcp 192.168.1.26:6443: i/o timeout` | portproxy Windows absent ou pointe sur mauvaise IP WSL | Étape 3, vérifier `wsl hostname -I` |
| `tls: certificate is valid for ... not 192.168.1.26` | cert k3s sans IP LAN dans SAN | Étape 10 (workaround) ou tls-san (propre) |
| `Unauthorized` | normal sans cert client | Étape 7-8 : kubeconfig avec cert client |
| Tout marchait, maintenant timeout | IP WSL a changé après reboot | Refaire étape 3 avec nouvelle IP |
