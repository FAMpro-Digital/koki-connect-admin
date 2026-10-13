# Éducation — Bibliothèque et Vue d'ensemble (Admin)

## Menu
La rubrique **🎓 Éducation** contient maintenant trois écrans (contrat Rubriques, identique dans les deux dépôts) :
- **Vue d'ensemble** : établissements et livres publiés / programmés / brouillons / archivés, livres gratuits (dont téléchargeables) et payants, et une liste **À vérifier** avec un bouton « Corriger » qui ouvre directement la fiche.
- **Établissements scolaires** : écran existant (phase 1), inchangé.
- **Bibliothèque (livres)** : recherche, filtres (Gratuits, Payants, Publiés, Programmés, Brouillons, Archivés, À vérifier), création et modification, **Publier maintenant / Dépublier**, **Archiver / Restaurer**, **Ouvrir le fichier**.

## Fiche livre
Titre, présentation, catégorie, niveau, format, accès Gratuit/Payant, prix en FCFA, auteur, fournisseur, WhatsApp, description, couverture, source, visibilité et date de publication.
- **Gratuit** : fichier PDF, EPUB, MP3 ou M4A, 50 Mo maximum. Le vrai format est vérifié sur les premiers octets (un fichier renommé est refusé). Remplacer ou retirer le fichier supprime l'ancien du stockage après enregistrement.
- **Payant** : aucun fichier publié ; commande par WhatsApp. Le paiement en ligne est une phase séparée.
- **Livre papier** : pas de fichier ; fournisseur et WhatsApp.

Points signalés « À vérifier » : livre gratuit sans fichier, livre payant sans WhatsApp, livre papier sans fournisseur ni WhatsApp, pas de couverture, niveau manquant ; établissement sans téléphone, horaires ou photo.

## Contrat et stockage
- `src/livre-contract.js` : contrat `koki.education.book` v1, **identique** à `assets/portail/livre-contract.js` du site public. Pas de nouvelle table : `koki_contents` (`Informations utiles` / `Éducation`).
- `supabase/proposals/education-bibliotheque.sql` (+ migration locale générée `20261011000470_education_bibliotheque.sql`) :
  - bucket privé **`koki-livres`**, 50 Mo, types PDF/EPUB/MP3/M4A ;
  - envoi : éditeurs avec MFA, dans leur propre dossier ;
  - lecture publique : **uniquement** le fichier d'un livre gratuit publié, visible à la date courante et non archivé (`koki_private.livre_gratuit_publie`) ; un livre payant, programmé, en brouillon ou archivé n'est jamais lisible ;
  - suppression : par son auteur, seulement si plus aucune fiche ne référence le fichier.

## À faire avant la mise en service
1. Appliquer la proposition SQL sur Supabase **local**, puis sur la préproduction autorisée. **Elle n'est pas appliquée en production** (aucune base distante modifiée).
2. Tester sur téléphone : envoi d'un PDF depuis l'Admin, téléchargement et lecture hors ligne dans l'application publique.

## Vérifications
- Règles SQL vérifiées sur PostgreSQL 16 local : public limité au livre gratuit publié ; brouillon, programmé, archivé, payant et texte non JSON refusés sans erreur ; envoi refusé sans MFA ou hors de son dossier ; suppression refusée tant que le fichier est référencé.
- `tests/education-bibliotheque.test.js` (PGlite, même scénario) et `tests/livres-admin.test.js` (formats, compteurs, alertes, routage).
- Compilation Vite et tests PGlite : exécutés par la CI GitHub (non disponibles hors ligne dans l'environnement de préparation).
