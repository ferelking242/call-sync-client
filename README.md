# CallSync Client

Client Flutter pair-à-pair pour recevoir les enregistrements CallSync.

## Fonctionnalités

- Reconnexion automatique au pair mémorisé.
- Manifeste distant et comparaison SHA-256.
- Téléchargement uniquement des nouveautés ou fichiers modifiés.
- Reprise d’un fichier interrompu via un fichier temporaire.
- Lecture audio locale après synchronisation.
- Aucun fichier stocké sur un serveur central. Le relais Internet éventuel ne
  fait que transmettre les commandes et les blocs audio en mémoire.

## Flux pair-à-pair

```text
[Téléphone source]
      |  CallSync surveille et expose le dossier
      |  manifeste + socket authentifiée
      v
[CallSync Client]
      |  compare les SHA-256 locaux
      -> télécharge les nouveautés/modifications
      -> reprend les fichiers partiels
      -> stocke localement
```

## Signature de l’APK

Le workflow GitHub produit une APK release installable directement. Il utilise
un keystore privé si les variables de CI sont disponibles ; sinon, pour le test,
il utilise le certificat debug Gradle afin d’éviter l’erreur Android « certificat
manquant ». Cette signature de test ne convient pas à une publication Play Store.

## Configuration

1. Ouvrez CallSync sur le téléphone source.
2. Copiez le code affiché dans la carte **Partage pair-à-pair**.
3. Ouvrez le client et allez dans **Paramètres**.
4. Collez le code et appuyez sur **Lier & synchroniser**.
5. Le client réessaie périodiquement lorsque le réseau est disponible.

Le client tente le protocole direct lorsque l’adresse annoncée est joignable.
Si ce n’est pas le cas, il utilise automatiquement le relais Internet indiqué
dans le code. Les deux téléphones peuvent être sur des réseaux différents ; le
relais ne stocke pas les fichiers.