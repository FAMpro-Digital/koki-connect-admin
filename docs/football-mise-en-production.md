# Module Football — plan de mise en production (PRÉPARATION, rien n'est exécuté)

Aucune étape de ce document n'est autorisée par sa simple présence : chacune demande l'**autorisation
écrite** du propriétaire (voir §6). Rien n'a été appliqué en production ; aucune requête n'a été envoyée
au projet `qsbmzzbiztfqysstepxm`.

## 1. Revue finale des migrations

| Point | Constat | Preuve |
|---|---|---|
| Empreinte de départ | la copie locale reproduit la production du 20/11/2026 : 560 objets, 0 écart | `verifier.sh` (CI, job `historique-sql`) |
| Ordre | `20261201000500_foot_schema` puis `20261201000600_foot_acces` ; chacune refuse une seconde application (garde) | `tester-foot.sh` §2 |
| Objets existants | **560/560 inchangés** après les deux migrations ; ajouts : 3 fonctions `public.koki_foot_*` et leurs droits, plus le schéma privé `koki_foot` | `comparer-ajouts.py`, `tester-foot.sh` §6 |
| Instructions DDL | toutes portent sur `koki_foot` ou `public.koki_foot_*` ; aucune sur `auth`, `storage`, `realtime` ou les tables existantes | revue du texte des migrations |
| RLS et droits | RLS activée sur toutes les tables `koki_foot`, aucune politique, aucun droit direct pour `anon`, `authenticated`, `service_role` | `tester-foot.sh` §3 (« conseil 0 ») et `foot.sql` |
| RPC | `koki_foot_public` (anon, authenticated) ; `koki_foot_admin` (rôle + aal2, `koki_private.allowed`) ; `koki_foot_sync` (service_role seul) ; toutes `SECURITY DEFINER`, `search_path=''` | `foot.sql` (242 tests) |
| Échec partiel | instruction cassée injectée à 10 endroits (début, 1/4, 1/2, 3/4, avant `commit`) : **rien n'est appliqué**, structure identique, puis la migration intacte passe | `tester-foot-echec-partiel.sh` |
| Retour arrière | `retour/0600` puis `retour/0500` : structure redevenue identique à la production (560/0) ; `0500` refuse de détruire des données sans `koki.retour_force=oui` | `tester-foot.sh` §4 |
| Réapplication | après retour, les migrations s'appliquent de nouveau | `tester-foot.sh` §5 |
| Version | migrations écrites pour PostgreSQL 17 (production) ; essais locaux sous 16 | — |

Limite : l'empreinte suit les schémas `public`, `koki_private`, `koki_social_private` ; l'intérieur de
`koki_foot` est couvert par `foot.sql`, et l'absence d'effet sur `auth`/`storage`/`realtime` par la revue.

## 2. Déroulé proposé (le jour J, avec autorisation)

1. **Sauvegarde** : vérifier la dernière sauvegarde automatique Supabase (ou la restauration à un
   instant, si le forfait l'inclut) et en noter l'heure ; en plus, export `pg_dump --schema-only` et
   export des données des schémas `public`/`koki_private`, conservés hors de Supabase.
2. **Empreinte avant** : exécuter `outils/empreinte.sql` en **lecture seule** sur la production et
   comparer à `reference/empreinte-production-2026-11-20.txt` (`comparer.py`). Tout écart : arrêt.
3. **Application** : `0500` puis `0600`, chacune dans sa transaction (c'est le cas du fichier) ; arrêt à
   la première erreur (aucun effet partiel, voir §1).
4. **Empreinte après** : `comparer-ajouts.py` doit afficher 560/560 inchangés et seulement des ajouts Football.
5. **Contrôles** : `koki_foot_public('accueil')` en anonyme ; `koki_foot_admin` refusé sans aal2 ;
   essais réels (`docs/football-tests-reels.md`) sur le projet d'essai au préalable.
6. Le module reste **invisible** : `config.json › modules.football` absent ou `false`,
   `VITE_KOKI_FOOT_ADMIN` absent.

**Retour arrière** : `retour/20261201000600_foot_acces.sql`, puis `retour/20261201000500_foot_schema.sql`
(bloqué si des données Football existent : décision explicite `koki.retour_force=oui`). Empreinte de
contrôle ensuite (560/0 attendu). Les autres modules ne sont pas touchés.

## 3. Branchement de l'administration

- Route `football`, entrée « ⚽ Football (scores en direct) » sous **Sport**, affichée seulement si
  `VITE_KOKI_FOOT_ADMIN` vaut exactement `true` (toute autre valeur : désactivé).
- À l'entrée de la route : drapeau, client configuré, rôle `read` ; puis `guard()` (session et aal2,
  mécanisme existant) avant **chaque** appel `koki_foot_admin`. Les droits réels sont vérifiés par le
  serveur. Aucune modification de l'authentification ; aucun accès aux tables.
- Vérifié : 4 tests statiques et un essai navigateur de l'application construite avec les deux valeurs
  du drapeau (drapeau absent : menu Sport à 5 entrées, aucune trace ; drapeau `true` : 6 entrées, écran
  « Connexion requise » sans serveur ; aucune erreur dans la console).

## 4. Vercel (constat en lecture seule, 24/11/2026)

- Le connecteur Vercel de cette session ne voit **aucun projet** (équipe « mourtadafam-5955's projects »
  vide pour ce jeton ; `koki-connect-admin` introuvable). Paramètres internes (protection des variables,
  branches de production, préversions) **non vérifiables d'ici** : à contrôler dans le tableau de bord.
- Constat GitHub (déploiements créés par `vercel[bot]`) :
  - site public : projet `kokiconnect221-ux/koki-connect` ; production depuis `main` (dernier le
    24/11 à 16 h 59) ; préversions actives ;
  - admin : projet `mourtadafam-5955s-projects/koki-connect-admin` ; production depuis `main` (dernier
    le 21/11) ; préversions actives ;
  - branche `feature/module-football` : **0 déploiement** dans les deux dépôts (`vercel.json ›
    git.deploymentEnabled` la bloque) ; aucun statut Vercel sur les commits des PR #63 et #144.
- **Risque** : `main` n'est **protégée** dans aucun des deux dépôts ; une fusion ou une poussée directe
  déclenche un déploiement de production automatique. Recommandation : protection de `main` (PR et
  vérifications obligatoires).
- À vérifier par le propriétaire : `VITE_KOKI_FOOT_ADMIN` absent en Production ; variables sensibles
  marquées « Sensitive » ; « Preview » sans clé `service_role`.

## 5. Logos (CSP inchangée)

La CSP actuelle n'autorise pas les images des fournisseurs ; les équipes s'affichent avec une pastille
de couleur et leurs initiales. Solution future, **non implémentée** : synchronisation qui télécharge le
logo côté serveur, le contrôle (type PNG/WebP/SVG nettoyé, taille ≤ 100 ko, dimensions), le stocke dans un
bucket public dédié `koki-foot-logos` de notre propre projet (nom = SHA-256 du contenu) et enregistre
`logo_url` vers ce bucket. La CSP reste inchangée : `img-src` du site public autorise déjà
`https://qsbmzzbiztfqysstepxm.supabase.co` (vérifié le 24/11/2026) ; repli sur la pastille si
le logo est absent. Demande : bucket, quota de stockage et droits d'usage des logos.

## 6. Opérations nécessitant l'autorisation écrite du propriétaire

1. Création d'un projet Supabase d'essai et des comptes d'essai (§ tests réels), puis exécution des essais.
2. Lecture seule de l'empreinte de production (§2 étape 2).
3. Application des migrations `0500` et `0600` en production.
4. Passage du canal Realtime `koki-foot` en canal privé avec politique RLS (réglage Realtime).
5. Fusion des PR #63 et #144 (déclenche un déploiement de production, `main` non protégée).
6. `VITE_KOKI_FOOT_ADMIN=true` (admin) puis `modules.football=true` (site public).
7. Abonnement éventuel à un fournisseur (API-Football) et dépôt de la clé en variable d'environnement.
8. Création du dépôt d'ancrage, de ses secrets et du workflow quotidien ; choix du service de courriel.
9. Protection de la branche `main` des deux dépôts.
