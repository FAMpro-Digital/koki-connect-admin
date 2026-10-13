# Éducation — Phase 1 : établissements scolaires

## Réalisé localement

Les deux dépôts restent sur `develop/phases-2-6`. Les modifications antérieures de la rubrique commerçants sont conservées. Aucun commit, push, déploiement ou changement de base distante pendant cette phase.

### Koki Connect Admin
- `src/education-admin.js` : écran dédié, recherche, création et modification, niveau et secteur, adresse/village, téléphone professionnel public, horaires, présentation, description, source, date et statut.
- Photo traitée par les composants existants de compression et téléversement dans `koki-media`, avec conservation de la référence et du contrôle de concurrence `updated_at`.
- Publication immédiate ou programmée ; archivage confirmé, sans suppression ; modifier une fiche archivée permet de la reprendre en brouillon ou de la republier.
- `src/app.js` : entrée Établissements scolaires et routage des fiches structurées vers leur interface dédiée. Le formulaire éditorial générique n’écrase pas le contrat scolaire.
- `src/education-contract.js` : contrat commun versionné.

### Koki Connect public
- `index.html` : les deux accès Éducation/Écoles ouvrent le catalogue scolaire ; accès à la carte conservé dans ce catalogue.
- `assets/portail/app.js` : catalogue des établissements publiés, recherche, filtre par niveau, fiche détaillée, photo et appel téléphonique ; chargement et erreur avec nouvelle tentative.
- `assets/portail/education-contract.js` : même contrat que dans Admin, à conserver identique lors des évolutions.

## Contrat commun et synchronisation

Aucune table supplémentaire et aucune migration nécessaires : réutilisation de `public.koki_contents`, identifiant UUID `id` inchangé, `type=Informations utiles`, `categorie=Éducation`. Le champ existant `texte` contient un objet JSON versionné : `schema=koki.education.school`, `version=1`, `niveau`, `secteur`, `telephone`, `horaires`, `description`, `archive`. Les autres champs partagés restent `titre`, `resume`, `lieu`, `source`, `publication`, `statut`, `image_path`.

Admin utilise les écritures éditoriales existantes. Le public utilise exclusivement le flux serveur `koki_public_feed` et les liens Storage existants. Les brouillons et dates futures sont filtrés côté serveur par les politiques existantes. Archiver écrit atomiquement `statut=brouillon` et `archive=true` ; le catalogue public ne reçoit plus la fiche lors de son prochain chargement. Les autres informations de catégorie Éducation ne sont pas converties ni supprimées.

Synchronisation à chaque ouverture du catalogue ou bouton Actualiser. Pas de canal Realtime ajouté. Une fiche déjà ouverte peut rester visible jusqu’au prochain chargement ; une URL d’image déjà signée reste valable jusqu’à son expiration existante (120 secondes). Ne renseigner que des informations destinées à être publiques. Aucun nouveau rôle ni affaiblissement de MFA, RLS, Storage ou CSP.

## Vérifications réalisées
- Vérification de syntaxe JavaScript des fichiers nouveaux et modifiés : réussie.
- Compilation Vite Admin, backend désactivé et sortie temporaire séparée : réussie (61 modules).
- Contrôle des différences Git : aucun défaut d’espacement signalé.
- Aucun fichier de tests ajouté, aucune campagne de tests lancée, conformément à la demande.

## Limites et validation restante

La publication réelle, l’archivage et l’affichage sur iPhone n’ont pas été exercés sur Supabase ou un déploiement. Il faut les valider dans un environnement de préproduction autorisé avant livraison. La rubrique ne crée pas automatiquement de points sur la carte et ne gère pas encore les cours, livres/PDF, examens, bourses, formations, achats ou paiements : phases suivantes soumises à validation. Le contrat structuré est validé dans les applications ; les autorisations et la visibilité restent imposées par les contrôles serveur éditoriaux existants.

Phase 1 prête à être revue localement. Attendre validation avant toute phase suivante, migration ou déploiement.
