# Espace Clubs & Académies — socle serveur (phase 3, étape 1)

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
| `supabase/historique/retour/20261201000*.sql` | Retours arrière (ordre inverse ; le dernier refuse de détruire des données sans `koki.retour_force=oui`) |
| `supabase/tests/sport-clubs.sql` | 105 vérifications |
| `supabase/historique/outils/tester-sport.sh` | Cycle complet local : référence → migrations → gardes → tests → retour → empreinte identique → réapplication |

Aucune table, fonction, règle ou bucket existant n'est modifié. Réutilisés tels quels (gardés par empreinte MD5) :
`koki_private.stamp()`, `koki_private.audit()`, `koki_private.allowed()`, `public.koki_localites`, `public.koki_audit`.

## Vérifier

```bash
PGHOST=/tmp bash supabase/historique/outils/tester-sport.sh   # PostgreSQL local uniquement
```

Résultat attendu : `identiques 549 | écarts 0`, gardes bloquantes, `Tests réussis : 105`, retour → `identiques 549 | écarts 0`.

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
| Administration (aal2) | `admin_clubs`, `admin_reports` (lecture) ; `admin_review`, `admin_create_club`, `admin_invite` (superadmin, manager) ; `admin_hide`, `admin_relay`, `admin_report_status` (superadmin, editor) | `koki_private.allowed()` inchangée |

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

## Reste à faire (étapes suivantes de la phase 3)

- Lot 11 : notifications (colonne additive `sport_ref` sur `koki_notifications`, décision D2) et envoi aux abonnés.
- Interfaces : espace académie (`koki-connect/assets/sport/club-space.mjs`), pages publiques, section admin `src/clubs-admin.js`,
  contrat partagé `clubs-contract.js`.
- Tests navigateur et mobiles (Playwright), suite `npm test` de l'admin (dépendances à installer).
