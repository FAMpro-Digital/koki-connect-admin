# Fiches commerçants — rapport du 10 octobre 2026

Développement local sur `develop/phases-2-6` dans les deux applications existantes. Aucune migration distante, aucune écriture dans Supabase réel, aucun déploiement ni push GitHub effectué pour cette fonctionnalité.

## Parcours réalisé

Dans Commerces & Services, le professionnel connecté peut remplir sa fiche : nom commercial, profil Commerçant ou Les deux, catégorie, adresse, coordonnées GPS, téléphone WhatsApp international, horaires, description et jusqu’à cinq photos facultatives. Le bouton de position réutilise `obtenirPositionActuelle`. L’inscription réservée aux prestataires de services et les autres fonctions du catalogue restent disponibles.

Les photos suivent le traitement existant : sélection jusqu’à 10 Mio, décodage selon le navigateur, compression et limite finale du bucket privé de 1 Mio par photo. L’aperçu et les poids avant/après sont affichés. Une erreur de traitement ou d’envoi ne remplace pas la fiche enregistrée. Les photos existantes peuvent être conservées ou retirées de la fiche ; aucun ancien fichier Storage n’est supprimé automatiquement.

La commande RPC `submit_merchant` impose `En attente` côté serveur. Les références de galerie sont dans `payload.photos`, la couverture dans `payload.image_path`, les autres champs dans le profil professionnel existant de `koki_records`. Aucun nouveau système de compte ou de géolocalisation.

L’administrateur autorisé Commerce avec MFA aal2 peut approuver, refuser ou suspendre la fiche. Le catalogue public et ses médias ne rendent accessibles que les profils actifs approuvés et les offres dont les parents sont actifs. Une correction replace la fiche en attente ; la validation porte sur une révision précise. Une fiche refusée peut être corrigée ; une fiche suspendue nécessite l’intervention administrative.

## Sécurité et compatibilité

- Propriétaire fixé depuis `auth.uid()`, jamais depuis le navigateur ; compte permanent requis.
- Champs autorisés, longueurs, téléphone international, coordonnées et galerie vérifiés en SQL.
- Cinq références média maximum, uniques, existantes et appartenant au commerçant.
- Révisions et verrou transactionnel par propriétaire : protection des modifications concurrentes et des validations périmées.
- Idempotence réutilisant `business_keys` : une reprise ne crée pas une seconde fiche.
- L’ancien accès direct à la fonction interne est retiré des rôles clients. Les autres commandes passent toujours par le routeur RPC public et conservent leurs contrôles.
- Les lecteurs publics ne reçoivent ni identifiant propriétaire ni informations administratives.
- Les politiques Storage existantes sont conservées ; les helpers tiennent compte de la galerie, de la validation et des références protégées contre la suppression.
- Les permissions Admin, le MFA, le journal d’audit existant, la CSP et les configurations de déploiement ne sont pas désactivés.

Référence de conception : [contrôle d’accès Supabase Storage par RLS](https://supabase.com/docs/guides/storage/security/access-control).

## SQL préparé, non appliqué

`supabase/proposals/merchant-profiles.sql` est une proposition incrémentale à examiner **après** `phase2-transactions.sql`. Elle élargit les statuts des professionnels, ajoute le routeur des fiches, conserve l’API `public.koki_business` et adapte la lecture des galeries.

Le générateur `scripts/prepare-test-installation.mjs` intègre cette proposition au paquet TEST atomique. Les fichiers générés dans `artifacts/phase4` restent exclus de Git. Le précontrôle exige toujours un projet vide ; aucun script n’applique automatiquement cette installation à un serveur.

## Fichiers concernés

Application publique :
- `assets/business/ui.mjs` : formulaire et suivi de la fiche, photos, reprise.
- `assets/business/runtime.mjs` : accès aux fiches professionnelles approuvées, horaires, localisation et galerie.
- `assets/business/business-state.js` : supervision des refus.
- `tests/merchant-client.test.cjs` : reprise RPC, absence de statut/propriétaire fourni par le client, activation désactivée.

Admin :
- `src/business-admin.js` : détails, galerie, filtres et décisions administratives avec révision.
- `src/business-ui.js` : composant partagé de fiche et traitement des photos.
- `src/business-state.js` : comptage des refus dans la supervision.
- `supabase/proposals/merchant-profiles.sql` et `scripts/prepare-test-installation.mjs`.
- `tests/helpers/business-db.js`, `tests/preproduction.test.js`, `tests/merchant-profiles.test.js`, `tests/business-concurrency.test.js`, `tests/business-phase6.test.js`.
- `tests/merchant-ui.html`, `tests/merchant-ui.js`, `scripts/test-merchant-browser.mjs` : essais locaux avec RPC et Storage simulés.

## Résultats

- **71 tests Admin réussis**, dont les contrôles SQL, RLS, médias privés, MFA et les vrais accès concurrents au PostgreSQL local.
- **17 tests publics réussis**.
- **4 parcours Chromium réussis** : composants public et partagé, écrans de 390 × 844 et 1440 × 900. Photo traitée puis visible après rechargement, affichage de la photo dans Admin, refus, correction, approbation, texte hostile non interprété en HTML, aucune erreur JavaScript ni débordement horizontal.
- Compilation Vite Admin et assemblage statique public réussis dans de nouveaux dossiers temporaires ; compilations locales existantes conservées.
- Vérifications de syntaxe JavaScript et `git diff --check` réussies.

Les tests SQL utilisent exclusivement PGlite et PostgreSQL locaux avec acteurs TEST. La suite Admin complète a été exécutée avec réseau sortant distant bloqué. Les réponses Storage du test navigateur sont interceptées et simulées : aucune requête n’est envoyée à Supabase.

Rejouer les tests automatisés : `npm test` côté Admin, `node --test tests/*.test.cjs` côté public. Pour les essais navigateur, définir `PLAYWRIGHT_MODULE_PATH` vers un module Playwright déjà installé et `KOKI_PUBLIC_ROOT` vers le dépôt public, puis lancer `node scripts/test-merchant-browser.mjs`. Aucune installation automatique.

## Limites et prochaines validations

- La fonctionnalité est prête dans le code local ; les modules métier restent désactivés dans les configurations actuelles. Aucun changement n’apparaît encore sur les sites en ligne.
- Autorisation nécessaire avant toute application du SQL à un Supabase TEST isolé, puis activation et préproduction coordonnée.
- Les vrais échanges Auth/RPC/Storage sur ce projet TEST restent à vérifier, ainsi que Safari sur un iPhone réel et Android. Une largeur mobile Chromium n’est pas un test Safari.
- Les URL signées déjà émises conservent leur durée de validité courte existante (120 secondes) ; la suspension retire immédiatement la fiche des nouvelles lectures du catalogue, sans révoquer rétroactivement ces URL.
- Les dépendances et certains objets Git avaient été déchargés par iCloud. Leur téléchargement local a permis les vérifications ; cela a retardé la première exécution sans nécessiter de réinstallation.
