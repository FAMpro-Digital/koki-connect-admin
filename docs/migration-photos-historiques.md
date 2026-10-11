# Photos historiques → dossiers anonymes : stratégie (non exécutée)

**Situation.** Depuis la phase 2, les nouvelles photos sont déposées dans un dossier anonyme propre à chaque compte (`koki_private.media_folders`). Les photos plus anciennes restent dans un dossier nommé par l'identifiant du compte (`<identifiant>/<fichier>.jpg`) : elles restent affichées (décision du 11 octobre 2026), mais leur adresse révèle cet identifiant.

**Rien n'est migré aujourd'hui.** Ce document décrit la marche à suivre, à valider avant toute exécution.

## Étapes proposées

1. **Inventaire (lecture seule)** : `supabase/preproduction/inventaire-photos-historiques.sql` compte, par rubrique et statut, les références historiques, les fichiers et les fichiers absents. Exécution locale, puis sur le projet TEST.
2. **Script de migration côté serveur** (jamais dans le navigateur, clé de service gardée hors de Git) :
   - pour chaque compte concerné : créer son dossier anonyme s'il n'existe pas ;
   - **copier** chaque fichier vers `<dossier anonyme>/<nouveau nom>` (copie Storage, l'original n'est pas touché) ;
   - remplacer les chemins dans `payload.image_path`, `payload.photos` et `payload.modification.photos`, fiche par fiche, avec contrôle de révision (aucune modification concurrente écrasée), sans changer le statut ni l'horodatage métier ;
   - journaliser chaque remplacement dans `koki_audit` (opération `MIGRATION_PHOTO`).
3. **Vérification** : catalogue public et administration affichent toutes les photos ; l'inventaire ne trouve plus de référence historique ; les commandes et demandes de service conservent leurs photos.
4. **Conservation** : les anciens fichiers restent en place pendant une période d'observation (proposée : 30 jours). Leur suppression est une étape séparée, soumise à votre accord explicite.
5. **Retour arrière** : tant que les anciens fichiers existent, il suffit de restaurer les anciens chemins depuis le journal.

## Points d'attention

- Photos de demandes de service (clients) : même principe, avec le dossier anonyme du client.
- Liens signés déjà émis : valables 2 minutes, sans effet durable.
- Ordre d'exécution : local → TEST → production, chacun avec autorisation.
