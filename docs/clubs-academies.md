# Espace Clubs & Académies — phase 3 (version isolée)

Branche `develop/clubs-academies` (non déployable : `vercel.json` › `git.deploymentEnabled`).
Conception complète et décisions D1–D9 : [clubs-academies-audit-conception.md](clubs-academies-audit-conception.md).

> **Rien n'est appliqué en production ni en test Supabase.** Les migrations sont **en attente** et ne figurent pas
> dans `supabase/historique/reference/ordre.txt` : la référence reste l'image exacte de la production
> (la CI `historique-sql` reste verte).

## Fichiers

| Fichier | Rôle |
|---|---|
| `supabase/historique/migrations/20261201000000_sport_schema.sql` | Schéma privé `koki_sport`, 20 tables, FK composites, déclencheurs (journal, révision, dernier responsable, retrait de consentement) |
| `supabase/historique/migrations/20261201000100_sport_access_rpc.sql` | `koki_sport.can()`, filtres de consentement, `public.koki_sport()` (connectés), `public.koki_sport_public()` (visiteurs), commandes `admin_*` |
| `supabase/historique/migrations/20261201000200_sport_storage.sql` | Bucket privé `koki-sport` (images 1 Mo) et 4 règles |
| `supabase/historique/migrations/20261201000300_sport_notifications.sql` | Colonne facultative `sport_ref` sur `koki_notifications` (3ᵉ cible), notifications membres / administrateurs / abonnés, **push uniquement** (`koki_notification_claim` exclut le module du SMS) |
| `supabase/historique/retour/20261201000*.sql` | Retours arrière (ordre inverse ; le dernier refuse de détruire des données sans `koki.retour_force=oui`) |
| `supabase/tests/sport-clubs.sql`, `supabase/tests/sport-notifications.sql` | 107 + 21 vérifications |
| `src/clubs-admin.js`, `src/clubs-contract.js` | Écran « 🎓 Clubs & Académies » (route `clubs`, accessible depuis Sport › Équipes et Matchs) : validation, refus/suspension motivés, académie pilote + invitation du responsable, signalements, masquage, relais |
| `tests/clubs-admin.test.js` | Contrat identique au public, décisions, branchement, aucune donnée de joueur côté administration |
| `supabase/historique/outils/tester-sport.sh` | Cycle complet local : référence → migrations → gardes → tests → retour → empreinte identique → réapplication |

Seules modifications d'éléments existants (migration 4, décision D2) : colonne ajoutée et contrainte élargie sur `public.koki_notifications`, une condition ajoutée dans `public.koki_notification_claim` (pas de SMS pour le module). Le retour arrière restaure la définition d'origine (empreinte identique vérifiée). Réutilisés tels quels (gardés par empreinte MD5) :
`koki_private.stamp()`, `koki_private.audit()`, `koki_private.allowed()`, `public.koki_localites`, `public.koki_audit`.

## Vérifier

```bash
PGHOST=/tmp bash supabase/historique/outils/tester-sport.sh   # PostgreSQL local uniquement
```

Résultat attendu : `identiques 549 | écarts 0`, gardes bloquantes, `Tests réussis : 107` et `21`, retour → `identiques 549 | écarts 0`.

## Commandes — `public.koki_sport(command, input)` (compte permanent connecté)

Toutes acceptent `request_id` (uuid, idempotence 48 h). Champs inconnus refusés. `revision` exigée pour toute modification.

| Domaine | Commandes | Permission |
|---|---|---|
| Compte | `my_clubs`, `create_club`, `accept_invitation` (renvoie `ok:false` si code faux ; 5 essais / 15 min, 20 / jour), `follow`, `unfollow`, `report` | compte connecté |
| Académie | `club_get` (lecture), `club_update` | membre / responsable + communication |
| Membres | `invite` (code à usage unique, 72 h, montré une seule fois), `invitation_cancel`, `member_update` | responsable |
| Catégories, encadrement | `category_save`, `staff_save` (`categories` = catégories confiées) | responsable |
| Joueurs | `players_list`, `player_get`, `player_save`, `player_archive` | responsable ; entraîneur limité à ses catégories |
| Représentants, consentements | `guardian_save`, `consent_save`, `consent_revoke` | responsable |
| Entraînements | `session_save`, `sessions_list`, `attendance_save`, `attendance_get` | responsable ; entraîneur (ses catégories) |
| Compétitions, matchs | `competition_save`, `team_add`, `team_delete`, `match_save`, `match_event_add`, `match_event_delete`, `standings` | idem |
| Communication | `post_save`, `post_publish` (académie `Actif`), `post_relay`, `tagging_list`, `media_add`, `media_list`, `media_hide`, `media_delete` | responsable + communication |
| Journal | `audit_list` | responsable |
| Administration (aal2) | `admin_clubs`, `admin_reports`, `admin_posts` (lecture) ; `admin_review`, `admin_create_club`, `admin_invite` (superadmin, manager) ; `admin_hide`, `admin_relay`, `admin_report_status` (superadmin, editor) | `koki_private.allowed()` inchangée |

## Lecture publique — `public.koki_sport_public(command, input)` (anon)

`clubs` · `club` (`slug` ou `id`) · `standings` (`competition_id`). Académies `Actif` uniquement.
Joueurs : seulement avec consentement actif (`prénom + initiale` ou `complet`), jamais l'année de naissance, les
représentants, les présences ni les téléphones. Médias : publics seulement si **tous** les joueurs désignés ont
l'autorisation photo (ou vidéo pour YouTube) ; « mineurs reconnaissables » sans joueur désigné → refusé à l'envoi.

## Points d'attention pour la mise en production (plus tard, avec accord écrit)

1. Relever une nouvelle empreinte de production en lecture seule et la comparer à `empreinte-production-2026-11-18.txt`.
2. Appliquer d'abord sur le projet TEST, puis seulement après accord sur la production ; alors seulement ajouter
   les trois fichiers à `reference/ordre.txt` et versionner la nouvelle empreinte.
3. `extensions.digest` et `extensions.gen_random_bytes` (pgcrypto) sont requis : présents en production dans `extensions`.

## Site public (dépôt koki-connect)

| Fichier | Rôle |
|---|---|
| `assets/sport/clubs-contract.js` | Contrat partagé (copie identique de `src/clubs-contract.js`, empreinte vérifiée par les tests des deux dépôts) |
| `assets/sport/clubs-public.js` | Onglet « 🎓 Académies » de la rubrique Sport, page d'une académie, Suivre, partage WhatsApp, signalement, lien `?academie=<slug>` |
| `assets/sport/club-space.js` | Espace académie : création, code d'invitation, tableau de bord, joueurs (fiches privées, représentants, autorisations parentales), entraînements et présences, matchs, compétitions et classement, publications et médias, équipe (catégories, encadrement, membres, invitations, journal), page publique |
| `assets/sport/clubs.css` | Styles (chargés seulement si le module est actif) |
| `assets/business/runtime.mjs` | Pont `window.KokiClubsAPI` (RPC, envoi de photos réencodées sans EXIF, liens signés 1 h) ; drapeau `clubsActif()` |
| `assets/portail/sport.js` | Onglet « Académies » ajouté seulement si le module est actif |
| `tests/clubs-academies.test.cjs` | 11 tests (contrat, activation, branchement, sécurité de l'affichage) |

**Activation :** le module reste **invisible** tant que `assets/business/config.json` ne contient pas `"clubs": true` dans `modules`.
Cette ligne est une modification de la configuration de production : à ajouter seulement après l'application des
migrations en production et votre accord écrit.

## Vérifications effectuées (20/11/2026)

- Base locale (réplique exacte de la production) : 107 + 21 tests, gardes, retour arrière → `identiques 549 | écarts 0`.
- Site public : `node --test tests/*.test.cjs` → 333/333.
- Administration : `node --test tests/*.test.js` → 133 réussis ; les 35 échecs sont identiques à l'état de départ (dépendance PGlite non installable dans l'environnement de travail), aucun nouvel échec.
- Navigateur (Chrome sans tête, 360 × 740 et 390 × 844, données issues de la base locale) : 10 écrans publics / espace académie et 4 écrans d'administration, aucune erreur JavaScript, aucun débordement horizontal.

## Reste à faire

- `npm test` complet de l'administration sur un poste avec dépendances installées (PGlite).
- Projet Supabase TEST : appliquer les 4 migrations, puis parcours réels sur téléphones (connexion SMS, envoi de photos, notifications push).
- Relais accepté → reprise dans le fil principal (aujourd'hui : décision enregistrée, reprise manuelle par un editor).
- Lecture des images privées par l'administration (logos d'académies à valider) : non prévue volontairement ; à décider.
