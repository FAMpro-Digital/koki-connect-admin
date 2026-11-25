# Dépôt d'ancrage du journal Football — modèle (NON créé, NON programmé)

Contenu de ce dossier, à copier dans un **dépôt GitHub PRIVÉ indépendant** (`FAMpro-Digital/koki-ancrage`)
après autorisation écrite :

| Fichier | Rôle |
|---|---|
| `ancrage-quotidien.yml.modele` | tâche quotidienne (23 h 55) : lecture, contrôle de continuité, signature, vérification de la série, archivage |
| `trousseau.exemple.json` | trousseau public des clés (rotation) |
| `generer-cle.mjs` | génération hors ligne d'une clé Ed25519 (clé privée hors dépôt, droits 600) |

## Mise en place (propriétaire)
1. Créer le dépôt privé `koki-ancrage` ; protéger `main` (poussée forcée et suppression interdites).
2. `node generer-cle.mjs ~/koki-ancrage-cle-1.pem` sur un poste de confiance ; copier l'entrée affichée
   dans `trousseau.json` du dépôt d'ancrage.
3. Environnement `ancrage` du dépôt d'ancrage, secrets : `KOKI_SUPABASE_URL`, `KOKI_SERVICE_KEY`
   (clé serveur du projet concerné), `KOKI_ANCRAGE_CLE_PEM` (contenu de la clé privée). Puis supprimer la
   copie locale de la clé privée ou la placer dans un coffre hors ligne.
4. Copier le modèle dans `.github/workflows/ancrage-quotidien.yml`.
5. Seconde copie indépendante : choisir le service (courriel à la direction FAMpro, ou second dépôt privé
   sous un autre compte) et compléter la dernière étape.

## Rotation des clés (tous les 6 mois, ou immédiatement en cas de doute)
1. Générer la nouvelle clé (`generer-cle.mjs`, `valide_du` = date de bascule).
2. Ajouter l'entrée au trousseau ; fixer `valide_au` de l'ancienne à la même date.
3. Remplacer le secret `KOKI_ANCRAGE_CLE_PEM` ; détruire l'ancienne clé privée.
4. L'ancienne clé publique reste dans le trousseau pour vérifier l'historique.

## Vérifications garanties (testées)
Signature et clé valide à la date du reçu ; chaîne des reçus (reçu manquant, remplacé, réordonné) ;
continuité du journal (réécriture d'une ligne ancrée **même après recalcul complet de la chaîne en base**) ;
troncature ; absence de secrets dans les reçus. Essai de bout en bout : `essai-ancrage.sh` (Supabase local).
