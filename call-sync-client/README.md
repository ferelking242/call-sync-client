# CallSync Client (Viewer)

Application Flutter — receveur d'enregistrements CallSync.

## Fonctionnalités

- **Connexion automatique** au serveur CallSync au démarrage
- **Téléchargement auto** de tous les enregistrements pas encore locaux
- **Déduplication SHA256** — ne télécharge jamais deux fois le même fichier
- **Lecture audio** locale (sans réseau) + streaming depuis le serveur
- **Purge du serveur** après confirmation que tous les fichiers sont locaux
- **Interface Material 3** propre et moderne (dark mode inclus)

## Build

### Prérequis

- Flutter ≥ 3.22.0
- Android SDK (API 24+)

### Build rapide

```bash
./build_release.sh
```

### Build signé

```bash
./build_release.sh my-key.jks store_password key_alias key_password
```

### Via GitHub Actions

Poussez un tag `v*` sur `main` → l'APK est buildé, signé et publié automatiquement.

## Flux de données

```
[Téléphone uploader]
      |  CallSync (Android) surveille le dossier
      |  → upload automatique vers le serveur
      ↓
[Serveur CallSync]
      |  Stocke les enregistrements (stockage temporaire)
      ↓
[CallSync Client - ce dépôt]
      |  Se connecte au démarrage
      |  → auto-télécharge tous les enregistrements manquants
      |  → stocke localement
      |  → peut purger le serveur une fois tout reçu
```

## Configuration

1. Ouvrez l'app → icône ⚙
2. Entrez l'URL de votre serveur CallSync
3. Entrez les identifiants (admin / admin123 par défaut)
4. Appuyez **Connecter & sauvegarder**
5. L'app se connectera automatiquement à chaque lancement
