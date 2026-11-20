# KOKI CONNECT — Module « Espace Clubs & Académies »
## Rapport d'audit (phase 1) et dossier de conception (phase 2)

Préparé le 20/11/2026 pour Mourtada Fam (FAMpro Digital). Premier partenaire pilote : Koki Académie Foot. Fonctionnement : **autonome**.

> **État : aucune modification n'a été faite.** Pas de SQL ni de migration en production, pas de déploiement, aucun changement d'utilisateur, de secret ou de variable. Les deux dépôts ont été clonés en **lecture seule** (accès public anonyme). Le schéma de production a été étudié **uniquement** à partir de l'historique versionné, rejoué dans une base PostgreSQL 16 locale et éphémère.
>
> Le développement (phase 3) ne commencera qu'après votre validation écrite de ce plan et de la section 9 (« Décisions à prendre »).

---

## Sommaire

1. Périmètre et méthode
2. Cartographie de l'existant
3. Comptes professionnels
4. Schéma Supabase, relations et RLS
5. Stockage et permissions
6. Composants réutilisables
7. Incompatibilités et risques relevés
8. Conception : architecture, données, rôles, RLS, mineurs
9. Décisions à prendre avant la phase 3
10. Plan de migrations
11. Plan de développement (phase 3)
12. Plan de tests (phase 4)
13. Ce qui reste interdit sans votre accord

---

## 1. Périmètre et méthode

| Élément | Version auditée |
|---|---|
| `FAMpro-Digital/koki-connect` (site public, JS sans compilation) | `f893b2e` — 18/11/2026 (PR #135) |
| `FAMpro-Digital/koki-connect-admin` (administration, Vite) | `7984f03` — 18/11/2026 (PR #58) |
| Schéma de production | Référence `supabase/historique` (37 fichiers, `reference/ordre.txt`) |

**Contrôle de fidélité.** L'outil du dépôt (`supabase/historique/outils/verifier.sh`) a rejoué les 37 fichiers dans une base locale, puis comparé le résultat à l'empreinte relevée en production le 18/11/2026 :
**549 éléments identiques, 0 écart.**

**Limite :** cette empreinte date du 18/11. Toute modification de production faite depuis n'est pas visible ici. Il faudra relever une nouvelle empreinte, en lecture seule, avant d'appliquer quoi que ce soit (voir §10).

---

## 2. Cartographie de l'existant

### 2.1 Application publique (`koki-connect`)

- Application web installable (PWA), statique, sans compilation : `index.html`, `sw.js`, `assets/portail/*` (rubriques) et `assets/business/*` (espace connecté).
- **Rubriques :** Accueil, Actualités, Annonces, Événements, Sports & ASC (`sport.js`, `classement.js`), Opportunités, Santé, Services publics, Éducation/Bibliothèque, Vidéos, Numéros utiles, Prières.
- **Espace connecté :** connexion par SMS ou e-mail (`client-access.mjs`). On y trouve l'espace professionnel Commerces & Services (`pro-space.mjs`), le catalogue public, le Transport (chauffeurs, courses) et les notifications (`notifications.mjs`).
- **Configuration production :** `assets/business/config.json` → `enabled: true`, modules commerce et transport actifs. `assets/portail/backend.json` pointe vers la production `qsbmzzbiztfqysstepxm` avec la clé *publishable* (publique par nature, normal).
- **Social :** j'aime, commentaires, blocage, modération (`koki_social_private`).
- **Tests :** 82 fichiers `tests/*.test.cjs`, plus `tests/e2e` (Playwright) et `tests/load` (k6, réservé à un projet TEST).

### 2.2 Application d'administration (`koki-connect-admin`)

- Vite, JavaScript. Supabase Auth avec **MFA TOTP obligatoire côté base** (`aal2`).
- **Modules :** publications, Commerce, Transport, Éducation/Livres, Santé, Lieux, Offres, Événements, Numéros utiles, Services publics, **Sport** (`sport-admin.js`), Vidéos, signalements, modération des commentaires, notifications, invitations administrateurs.
- **Fonctions serveur Vercel :** `api/invite-admin.js` et `api/notifications-dispatch.js` (clé service_role côté serveur uniquement).
- **Garde-fous d'environnement** (`src/environment-guard.js`) : refus de démarrer si l'environnement et la base ne correspondent pas.
- **Tests :** 63 fichiers `tests/*.test.js`, avec le SQL réel exécuté sur PGlite.

### 2.3 Module Sport existant (important)

Un module **« Sports & ASC »** existe déjà :

- Les équipes (ASC) et les matchs sont stockés dans `public.koki_contents` (`type = 'Sports & ASC'`), sous forme de JSON versionné dans la colonne `texte` (`sport-contract.js`, identique dans les deux dépôts).
- Il est saisi **uniquement par les administrateurs FAMpro**. Le classement est calculé (3/1/0).
- **L'effectif d'une équipe (nom, numéro, poste des joueurs) est publié tel quel**, sans aucun mécanisme de consentement.

➡ Ce module convient à des ASC adultes. **Il ne doit pas servir pour les joueurs mineurs d'une académie.** Le nouveau module doit coexister avec lui sans le remplacer (voir décision D8).

---

## 3. Comptes professionnels

| Constat | Détail |
|---|---|
| Identité | Compte Supabase Auth (SMS ou e-mail). Un déclencheur sur `auth.users` crée `public.koki_users`. |
| Fiche professionnelle | Ligne `public.koki_records` avec `kind = 'professionnels'`, `owner_id = auth.uid()`, statut `À valider → Actif / Refusé (motif obligatoire) / Suspendu / Archivé` |
| Unicité | Index unique `koki_professional_account` : **une seule fiche professionnelle par compte** |
| Effet automatique | Le déclencheur `initial_shop_after_profile` **crée une boutique** dès qu'une fiche professionnelle est créée |
| Écritures | Uniquement par la RPC `public.koki_business(command, input)`, qui aiguille vers des fonctions `SECURITY DEFINER` du schéma `koki_private` |
| Validation | Par l'administration (rôles `manager` ou `superadmin`, MFA). Le refus motivé est imposé par le déclencheur `koki_refus_motive`. |

**Conclusion :** on réutilise le **compte** (connexion, session, « Mon compte », notifications), mais **pas** la fiche `professionnels`. Elle est propre au commerce : elle déclenche la création d'une boutique, et son unicité empêcherait un commerçant de gérer aussi une académie.

---

## 4. Schéma Supabase, relations et RLS

### 4.1 Inventaire (production au 18/11)

- **Schémas :** `public`, `koki_private`, `koki_social_private`
- **38 relations, 69 fonctions, 54 politiques RLS, 13 déclencheurs, 3 buckets, 2 tâches planifiées**

**Tables `public` :**

- `koki_contents` (+ `koki_content_images`, `koki_content_media`, `koki_content_notified`)
- `koki_records` (registre métier générique : `kind` + `payload` JSONB), avec `koki_order_items` et `koki_reviews`
- Notifications : `koki_notifications`, `koki_notification_deliveries`, `koki_notification_preferences`, `koki_push_subscriptions`
- Utilisateurs et administration : `koki_users`, `koki_user_interests`, `koki_admin_members`, `koki_audit`, `koki_activity`
- Divers : `koki_localites`, `koki_transport_rates`

**Tables privées :** codes, devis, notes et signalements de courses, signalements de fiches, archives, dossiers photo, clés d'idempotence.

### 4.2 Modèle de sécurité en place

- `koki_private.allowed(permission)` : administrateurs uniquement, **session `aal2` exigée**. Rôles : superadmin, editor (`content`), manager (`commerce`, `transport`), analyst (lecture).
- Les tables sensibles sont dans des schémas privés, sans droits directs. L'accès passe par des **RPC `SECURITY DEFINER` avec `search_path = ''`**.
- **Journal :** `koki_private.audit()`. Ce déclencheur est générique et réutilisable sur toute table qui a les colonnes `id`, `revision` et `statut`.
- **Contraintes strictes sur `koki_records`** : liste fermée de `kind`, statuts autorisés par type, liens obligatoires.
- **Notifications :** `koki_notifications` exige **exactement une cible**, soit `record_id` (→ `koki_records`), soit `content_id` (→ `koki_contents`). C'est la contrainte `koki_notifications_cible`.

### 4.3 Points faibles constatés (sans lien direct avec le module)

- Avertissement Supabase connu : protection des mots de passe divulgués indisponible sur le forfait gratuit.
- Au 18/11, 1 administrateur sur 2 n'avait pas activé sa double authentification (d'après `docs/environnements-et-securite.md`).

---

## 5. Stockage et permissions

| Bucket | Taille / types | Écriture | Lecture publique |
|---|---|---|---|
| `koki-media` | 1 Mo, JPEG/PNG/WebP | Administrateurs, **et tout compte permanent dans son propre dossier** (`business_media_insert`, dossier alias anonyme) | Si l'image est référencée par un contenu publié, ou par une fiche commerce publiée |
| `koki-videos` | 30 Mo, MP4/WebM | superadmin / editor | Si la vidéo est rattachée à un contenu publié |
| `koki-livres` | 50 Mo | editor | Livres gratuits publiés |

Les règles de lecture publique de `koki-media` dépendent des contenus éditoriaux et du commerce. Y ajouter les académies compliquerait ces règles pour tout le monde. **Il faut donc un bucket dédié** (voir §8.6).

---

## 6. Composants réutilisables

| Composant | Réutilisation proposée |
|---|---|
| Supabase Auth + `client-access.mjs` (SMS / e-mail) | Connexion des responsables et entraîneurs |
| Squelette de `pro-space.mjs` (étapes, bouton « ← Retour », historique, statuts expliqués) | Espace académie |
| `image-processing.mjs` (compression sur le téléphone) | Logos, photos, médias |
| `koki_private.audit()` + `koki_audit` | Journal des écritures du module |
| Modèle « refus motivé » | Validation des académies |
| `koki_notifications` + `notifications-dispatch` (push/SMS) | Notifications aux abonnés et aux membres |
| `koki_contents` (type `Sports & ASC`) | Relais facultatif d'une actualité d'académie vers le fil principal, après modération FAMpro |
| `koki_social_private` | Plus tard : commentaires sur les actualités d'académie (hors phase 3) |
| `koki_localites` | Localisation de l'académie |
| `sport-contract.js` (disciplines, statuts de match, classement 3/1/0) | Mêmes listes et même règle de calcul |
| Outils `supabase/historique` (garde, retour arrière, empreinte, CI) | Toutes les migrations du module |
| PGlite (tests SQL de l'admin) et Playwright (mobile) | Tests RLS et inter-académies |

---

## 7. Incompatibilités et risques relevés

| # | Constat | Gravité | Mesure |
|---|---|---|---|
| R1 | Les branches de `koki-connect` se déploient **par défaut** en prévisualisation Vercel, sauf si elles sont listées dans `git.deploymentEnabled`. Or ce dépôt lit `backend.json`, qui pointe vers **la production**. Une prévisualisation de branche parlerait donc à la base de production. | **Élevée** | Avant tout push en phase 3 : ajouter la branche du module à `deploymentEnabled: false` dans **les deux** dépôts. Ne tester que sur Supabase local ou sur le projet TEST. |
| R2 | Les réglages Vercel *Preview* → base TEST (`docs/environnements-et-securite.md` §3) sont décrits comme « à faire après accord » : on ne sait pas s'ils sont appliqués. | Élevée | À confirmer par vous dans le tableau de bord Vercel. Je n'ai pas accès à Vercel. |
| R3 | L'empreinte de production date du 18/11 ; un écart éventuel depuis est inconnu. | Moyenne | Nouvelle empreinte en lecture seule juste avant la mise en production. Le premier fichier de migration s'arrête de lui-même si l'état n'est pas celui attendu. |
| R4 | `koki_records` : liste de `kind` fermée, contraintes croisées, déclencheurs commerce et transport. Y ajouter les académies obligerait à modifier 5 contraintes du cœur métier. | Élevée si on l'étend | Schéma séparé `koki_sport` (décision D1). |
| R5 | `koki_notifications` n'accepte que deux cibles (`record_id` XOR `content_id`). | Moyenne | Ajout additif d'une 3ᵉ cible (décision D2). |
| R6 | Fiche `professionnels` : unique par compte et créatrice automatique de boutique. | Moyenne | Ne pas l'utiliser pour les académies (§3). |
| R7 | Le module Sport existant publie les effectifs sans consentement. | Élevée pour des mineurs | Le réserver aux ASC adultes. Afficher un avertissement dans l'admin (décision D8). |
| R8 | `koki-media` accepte des images de tout compte connecté (1 Mo, dossier personnel). | Faible | Bucket `koki-sport` avec contrôle d'appartenance à l'académie. |
| R9 | Pas de base de test garantie à ce stade (projet TEST `euvxtwmyoihnutifshay` mentionné, état inconnu). | Moyenne | Phase 3 en local (rejeu de l'historique + PGlite). Le projet TEST seulement avec votre accord. |

Aucun secret n'a été trouvé dans les dépôts : seules la clé *publishable* et des références à des variables d'environnement y figurent.

---

## 8. Conception

### 8.1 Architecture fonctionnelle

```
                    ┌──────────────────── Site public (JS statique) ───────────────────┐
 Visiteur ─────────▶│ Sports & ASC › Clubs & Académies (liste, page académie, matchs,   │
                    │ résultats, classements, actualités)  ── RPC koki_sport_public()  │
 Compte connecté ──▶│ « Suivre », notifications                                         │
 Membre académie ──▶│ Espace académie (assets/sport/club-space.mjs) ── RPC koki_sport() │
                    └──────────────────────────────────────────────────────────────────┘
                                             │  (clé publishable, JWT utilisateur)
                    ┌──────────── Supabase ──▼─────────────────────────────────────────┐
                    │ public.koki_sport(command,input)  ─▶ koki_sport.* (SECURITY DEFINER)│
                    │ public.koki_sport_public(command,input) ─▶ lecture filtrée        │
                    │ schéma koki_sport : tables privées, RLS activée, aucun droit direct│
                    │ koki_sport.can(club, permission)  ← contrôle unique d'accès        │
                    │ bucket koki-sport (privé)  ← règles fondées sur can() et consentements│
                    │ koki_audit (journal) · koki_notifications (3ᵉ cible)              │
                    └──────────────────────────────────────────────────────────────────┘
                                             ▲
 Administration FAMpro (Vite, MFA aal2) ─────┘  section « Clubs & Académies » : validation,
                                                 suspension, modération, signalements
```

Ce découpage suit le modèle déjà en place pour le commerce : un **schéma privé**, une **RPC de commandes** unique, **aucun accès direct aux tables**, et des **contrôles en base**.

### 8.2 Modèle de données (schéma `koki_sport`)

Toutes les tables ont un `id uuid`. Les tables métier ont aussi `created_at`, `updated_at`, `revision` et `statut`, ce qui permet de réutiliser `koki_private.audit()`.
**Chaque table porte un `club_id`.** Les clés étrangères sont **composites** (`club_id, id`) : une ligne ne peut jamais pointer vers un objet d'une autre académie, même en cas de bogue applicatif.

| Table | Rôle | Champs principaux | Visibilité publique |
|---|---|---|---|
| `clubs` | Académie ou club | `type` (académie/club), nom, slug, statut (`À valider`, `Actif`, `Suspendu`, `Refusé`, `Archivé`), motif de refus, présentation, historique, activités, localité (→ `koki_localites`), adresse, GPS facultatif, téléphone et WhatsApp publics, logo, couleurs, discipline | Oui, si `Actif` |
| `club_members` | Personnes qui gèrent l'espace | club, `user_id` (→ `auth.users`), rôle (`responsable`, `entraineur`, `communication`), statut (`invité`, `actif`, `retiré`), invité par | Non |
| `club_invitations` | Invitations de collaborateurs | club, rôle, empreinte du code (jamais le code en clair), expiration (72 h), utilisée le | Non |
| `categories` | Catégories d'âge | club, nom (U9, U11…), années de naissance min/max, ordre | Oui (nom seulement) |
| `staff` | Encadrement | club, `user_id` facultatif, prénom, nom, fonction, téléphone (privé), photo, `public` (oui/non) | Si `public` |
| `staff_categories` | Catégories confiées à un entraîneur | staff, catégorie | Non |
| `players` | Fiche joueur **privée** | club, catégorie, prénom, nom, **année** de naissance (pas la date complète, voir D5), poste, numéro, photo, statut (`actif`, `archivé`), date de sortie | Selon consentement uniquement |
| `player_guardians` | Représentant légal | joueur, nom, lien, téléphone | **Jamais** |
| `player_consents` | Autorisations parentales | joueur, `nom_public` (`aucun` / `prénom + initiale` / `complet`), `photo`, `video`, `stats`, recueilli le, recueilli par, mode (papier / oral / WhatsApp), retiré le | **Jamais** (sert de filtre) |
| `sessions` | Entraînements | club, catégorie, début, fin, lieu, thème, statut (`planifié`, `annulé`, `réalisé`) | Oui, sans liste de joueurs |
| `attendance` | Présences | séance, joueur, présent, remarque | **Jamais** |
| `competitions` | Championnats, coupes, tournois, amicaux | club, nom, saison, type, catégorie, organisateur (texte) | Oui |
| `competition_teams` | Équipes engagées (dont adversaires saisis par nom) | compétition, nom, `is_self` | Oui |
| `matches` | Rencontres | club, compétition (facultative), catégorie, équipes (domicile / extérieur → `competition_teams` ou nom libre), date, lieu, statut (`À venir`, `En direct`, `Terminé`, `Reporté`, `Annulé`), scores | Oui |
| `match_events` | Buts, passes, cartons | match, joueur, type, minute | Seulement si consentement `stats` + `nom_public` ≠ aucun |
| `posts` | Actualités et annonces de l'académie | club, type (actualité / annonce / événement / performance), titre, texte, statut (`brouillon`, `publié`, `masqué`), publication, masqué par, motif, relais demandé | Si `publié` et académie `Actif` |
| `media` | Photos et vidéos | club, post (facultatif), chemin de stockage **ou** identifiant YouTube, type, `contient_mineurs`, statut | Voir règle §8.5 |
| `media_players` | Joueurs identifiables sur un média | média, joueur | Non (sert de filtre) |
| `follows` | Abonnements « Suivre l'académie » | `user_id`, club, notifications (oui/non) | Non (compteur seulement) |
| `reports` | Signalements par le public | cible (club / post / média), motif, statut, note admin | Non |

**Classements :** une vue calculée sur les matchs `Terminé` d'une compétition (3 points la victoire, 1 le nul, 0 la défaite), comme le module existant. Les statistiques individuelles se calculent depuis `match_events`, avec le même filtre de consentement.

### 8.3 Matrice des rôles et permissions

Légende : ✅ autorisé · 👁 lecture · ⛔ refusé · 🔸 limité (voir note)

| Action | Visiteur | Compte connecté | Responsable | Entraîneur | Communication | Admin FAMpro (aal2) |
|---|---|---|---|---|---|---|
| Voir une page d'académie active | 👁 | 👁 | 👁 | 👁 | 👁 | 👁 (aussi non actives) |
| Suivre / ne plus suivre | ⛔ | ✅ | ✅ | ✅ | ✅ | — |
| Demander la création d'une académie | ⛔ | ✅ (→ `À valider`) | — | — | — | — |
| Valider / refuser (motif) / suspendre | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ✅ superadmin, manager |
| Modifier présentation, logo, coordonnées | ⛔ | ⛔ | ✅ | ⛔ | ✅ | ⛔ (modération seulement) |
| Inviter / retirer des membres, changer leurs rôles | ⛔ | ⛔ | ✅ | ⛔ | ⛔ | ✅ superadmin (dépannage) |
| Gérer les catégories | ⛔ | ⛔ | ✅ | ⛔ | ⛔ | ⛔ |
| Gérer l'encadrement | ⛔ | ⛔ | ✅ | ⛔ | ⛔ | ⛔ |
| Créer / modifier / archiver des joueurs | ⛔ | ⛔ | ✅ | 🔸 ses catégories | ⛔ | ⛔ |
| Voir les fiches privées des joueurs | ⛔ | ⛔ | ✅ | 🔸 ses catégories | ⛔ | ⛔ (sauf signalement, journalisé) |
| Saisir et modifier les consentements | ⛔ | ⛔ | ✅ | ⛔ | ⛔ | ⛔ |
| Entraînements et présences | ⛔ | ⛔ | ✅ | 🔸 ses catégories | ⛔ | ⛔ |
| Matchs, compétitions, résultats | ⛔ | ⛔ | ✅ | 🔸 ses catégories | ⛔ | ⛔ |
| Publier actualités et médias | ⛔ | ⛔ | ✅ | ⛔ | ✅ | ⛔ |
| Masquer une publication ou un média | ⛔ | ⛔ | ✅ (les siens) | ⛔ | ✅ (les siens) | ✅ editor, superadmin |
| Relayer une actualité vers le fil principal | ⛔ | ⛔ | demande | ⛔ | demande | ✅ editor, superadmin |
| Signaler un contenu | ⛔ | ✅ | ✅ | ✅ | ✅ | — |
| Lire le journal | ⛔ | ⛔ | 🔸 sa propre académie | ⛔ | ⛔ | ✅ superadmin |

**Règles transversales :**

- Les membres d'une académie `À valider`, `Refusé` ou `Suspendu` gardent la lecture de leur espace, mais **ne publient rien**.
- Il y a toujours **au moins un responsable actif** : le dernier ne peut pas se retirer.
- Les rôles administrateurs existants sont réutilisés **sans modifier `koki_private.allowed()`** : `superadmin`/`manager` pour la validation, `editor` pour la modération.

### 8.4 Contrôle d'accès en base (RLS et fonctions)

1. **Schéma `koki_sport` fermé.** `revoke all` à `anon`, `authenticated` et `public`. RLS **activée sur chaque table, sans politique d'accès** pour ces rôles : refus par défaut, même en cas d'erreur de droits.
2. **Une seule fonction de décision :** `koki_sport.can(p_club uuid, p_permission text, p_category uuid default null) returns boolean`, en `SECURITY DEFINER` avec `search_path = ''`. Elle vérifie :
   - un compte permanent (pas anonyme) ;
   - une ligne `club_members` active pour `auth.uid()` ;
   - le rôle requis par la permission ;
   - le statut de l'académie, si la permission est une écriture ;
   - pour un entraîneur, l'affectation à la catégorie concernée.
3. **RPC de commandes** `public.koki_sport(command text, input jsonb)` :
   - même forme que `koki_business` : liste blanche de clés, taille limitée à 64 Ko, idempotence ;
   - chaque commande commence par charger l'objet, **déduit le `club_id` depuis la base** (jamais depuis la requête), puis appelle `can()` ;
   - accès refusé = erreur `42501`.
4. **RPC publique** `public.koki_sport_public(command, input)`, exécutable par `anon`. Elle ne renvoie que des champs en liste blanche, uniquement pour les académies `Actif`. Les données des joueurs y passent par le **filtre de consentement** (§8.5).
5. **Clés étrangères composites** (`club_id`, `id`) entre `players` ↔ `categories`, `attendance` ↔ `sessions`/`players`, `matches` ↔ `competitions`, `match_events` ↔ `players`, `media_players` ↔ `players`… L'isolation tient **même si une fonction est boguée**.
6. **Déclencheurs :** `koki_private.audit()` sur les tables métier, horodatage et révision par le serveur, refus motivé obligatoire, garde « dernier responsable ».
7. **Administration :** commandes `admin_*` réservées à `koki_private.allowed('commerce')` ou `allowed('content')` selon l'action (aal2 obligatoire), et journalisées.

### 8.5 Règles de protection des mineurs

1. **Privé par défaut.** Un joueur sans consentement enregistré n'apparaît **nulle part** publiquement : ni nom, ni photo, ni statistiques. Les effectifs publics affichent seulement un **nombre** par catégorie.
2. **Consentement granulaire du représentant légal :** forme du nom (`aucun` / `prénom + initiale` / `complet`), photo, vidéo, statistiques. Il est saisi par le responsable, qui indique la date et le mode de recueil (formulaire papier recommandé, modèle fourni).
3. **Retrait immédiat.** Le filtre est calculé **à chaque lecture**, jamais recopié. Un consentement retiré masque tout dès la requête suivante, y compris les anciens médias.
4. **Médias :**
   - un média qui montre des joueurs identifiables doit les désigner (`media_players`). Il n'est public que si **tous** ont l'autorisation photo ou vidéo ;
   - un média marqué « contient des mineurs » sans joueur désigné reste **privé** jusqu'à confirmation explicite du responsable ;
   - la modération FAMpro peut tout masquer.
5. **Jamais publiés, jamais renvoyés par la RPC publique :** date ou année de naissance, téléphone, adresse, représentant légal, présences, remarques, consentements.
6. **Minimisation :** pas de date de naissance complète (l'année suffit pour la catégorie). **Aucune donnée de santé** (pas de champ médical ni de champ « remarques » libre sur la fiche joueur), pour éviter les données sensibles.
7. **Photos :** compressées sur l'appareil, **métadonnées EXIF (dont GPS) retirées** avant l'envoi, chemins de fichiers aléatoires sans identifiant.
8. **Conservation :** les fiches archivées sont supprimées automatiquement après une durée à fixer (décision D5 ; proposition : 12 mois après la sortie). Les résultats d'équipe restent, les noms sont anonymisés.
9. **Journal :** création, modification, consentement, consultation administrateur d'une fiche joueur.
10. **Cadre légal :** au Sénégal, la référence est la loi n° 2008-12 du 25 janvier 2008 sur la protection des données à caractère personnel, sous le contrôle de la Commission de protection des données personnelles (CDP) ([vie-publique.sn](https://www.vie-publique.sn/documents/438/loi-protection-donnees-a-caractere-personnel), [osiris.sn](https://www.osiris.sn/le-senegal-va-reviser-la-loi-sur-la-protection-des-donnees-personnelles.html)). Une révision de cette loi est annoncée depuis plusieurs années ; je n'ai pas vérifié si un nouveau texte a été adopté. **Je ne suis pas juriste :** les formalités auprès de la CDP (déclaration, mentions d'information, durée de conservation) sont à confirmer avec elle ou avec un conseil avant l'ouverture au public.

### 8.6 Stockage

Nouveau bucket **privé** `koki-sport` : images de 1 Mo au maximum (JPEG, PNG, WebP).

- **Chemin :** `<club_id>/<uuid aléatoire>.webp`.
- **Écriture :** `koki_sport.can(club_id du dossier, 'media')`.
- **Suppression :** même règle, plus un contrôle que le média n'est plus référencé.
- **Lecture publique :** fonction `koki_sport.public_media(name)`. Le média doit être référencé par un logo, un membre de l'encadrement public ou un post publié d'une académie `Actif`, **et** respecter la règle des mineurs (§8.5-4).
- **Lecture des membres :** `can(club, 'read')`.
- **Vidéos (phase 3) :** liens YouTube uniquement (`media.youtube_video_id`). Un envoi direct de vidéos serait une étape ultérieure (décision D7).

### 8.7 Notifications

- **Abonnés** (`follows`, notifications activées) : nouvelle actualité publiée, match programmé ou reporté, résultat final.
- **Membres :** invitation reçue, académie validée, refusée (avec motif) ou suspendue, contenu masqué par la modération.
- **Administrateurs FAMpro :** nouvelle académie à valider, nouveau signalement.
- **Mécanisme :** insertion dans `koki_notifications`, puis envoi par `notifications-dispatch` (push, SMS selon les préférences). L'envoi existant n'est pas modifié.
- **Anti-spam :** au plus un résultat par match ; actualités regroupées si plus de 3 dans l'heure.

### 8.8 Interfaces

**Public** (`koki-connect`, sans compilation) :

- Nouveaux fichiers :
  - `assets/sport/clubs-contract.js` (contrat partagé : listes, validations, encodage ; identique dans l'admin) ;
  - `assets/sport/clubs-public.js` (liste et page académie, intégrées à la rubrique Sports & ASC) ;
  - `assets/sport/club-space.mjs` (espace académie, chargé après connexion, sur le modèle de `pro-space.mjs`) ;
  - `assets/sport/club-space.css`.
- Modifications **minimales** et additives : une entrée dans la rubrique Sports, le chargement différé des modules, le cache `sw.js`, la CSP si nécessaire.
- Le partage WhatsApp de la page académie réutilise `api/partage.js`.

**Admin** (`koki-connect-admin`, Vite) :

- `src/clubs-contract.js` (copie identique), `src/clubs-admin.js` (liste, validation, refus motivé, suspension, modération, signalements, journal).
- Une entrée dans `navigation-admin.js`.

---

## 9. Décisions à prendre avant la phase 3

| # | Question | Ma recommandation |
|---|---|---|
| **D1** | Où stocker les académies ? Nouveau schéma `koki_sport` **ou** extension de `koki_records` ? | **Schéma `koki_sport`** : aucun changement au cœur Commerce/Transport, isolation nette. |
| **D2** | Notifications : ajouter une 3ᵉ cible facultative `sport_ref uuid` à `koki_notifications` (colonne nullable et contrainte élargie, **seule modification d'une table existante**) **ou** une boîte de notifications séparée ? | **Colonne additive** : réutilise l'envoi push/SMS existant. Retour arrière simple. |
| **D3** | Actualités d'académie : uniquement sur la page de l'académie, **ou** relais au fil principal après validation FAMpro ? | Page de l'académie, avec **relais sur demande** validé par un editor. |
| **D4** | Les entraîneurs voient-ils tous les joueurs, ou seulement leurs catégories ? | **Seulement leurs catégories** (minimisation). |
| **D5** | Année de naissance seulement ? Durée de conservation après la sortie d'un joueur ? | Année seulement. **12 mois**, puis anonymisation. |
| **D6** | Qui peut demander la création d'une académie ? | Tout compte permanent → `À valider` → validation FAMpro. Pour le pilote : création directe par FAMpro et invitation du responsable de Koki Académie Foot. |
| **D7** | Vidéos : liens YouTube seulement au début, **ou** envoi direct (stockage plus coûteux, modération plus lourde) ? | **YouTube seulement** pour le pilote. |
| **D8** | Module Sports & ASC existant : le garder tel quel, avec un avertissement « ne pas saisir de joueurs mineurs » dans l'admin ? | **Oui.** La convergence des deux modules sera étudiée après le pilote. |
| **D9** | Où tester ? Local uniquement, **ou** aussi le projet Supabase TEST `euvxtwmyoihnutifshay` ? | Local d'abord. Le projet TEST pour les tests mobiles réels, **avec votre accord**. |

---

## 10. Plan de migrations

Les migrations suivent les règles de `supabase/historique/README.md` : chaque fichier a son **retour arrière**, commence par une **garde**, est ajouté à `reference/ordre.txt` et est vérifié par `outils/verifier.sh` et la CI.

| Ordre | Fichier (`supabase/historique/migrations/`) | Contenu | Retour arrière |
|---|---|---|---|
| 1 | `20261201000000_sport_schema.sql` | Garde (absence de `koki_sport`, empreintes de `koki_audit`/`audit()` attendues). Schéma, tables, contraintes, FK composites, index, RLS activée, révocations. | `drop schema koki_sport cascade` (vide au moment du retour) |
| 2 | `20261201000100_sport_access.sql` | `can()`, filtres de consentement, déclencheurs (audit, horodatage, dernier responsable, refus motivé) | Suppression des fonctions et déclencheurs |
| 3 | `20261201000200_sport_rpc.sql` | `public.koki_sport()`, `public.koki_sport_public()`, droits d'exécution | Suppression des deux RPC |
| 4 | `20261201000300_sport_storage.sql` | Bucket `koki-sport` et ses politiques | Suppression des politiques ; bucket supprimé s'il est vide |
| 5 | `20261201000400_sport_notifications.sql` | **(Si D2 validée)** colonne `sport_ref` + contrainte `cible` élargie + déclencheurs de notification | Restaure la contrainte d'origine (bloqué s'il existe des lignes `sport_ref`) |
| 6 | `20261201000500_sport_admin.sql` | Commandes `admin_*` (validation, modération, signalements) | Suppression |

**Ordre d'application :** base locale → projet TEST (si D9) → **production uniquement après votre accord écrit**.

**Avant la production :**

- nouvelle empreinte en lecture seule ;
- export des tables touchées (seule `koki_notifications` l'est, si D2) ;
- sauvegarde quotidienne Supabase vérifiée.

---

## 11. Plan de développement (phase 3)

Le travail se fera sur une branche dédiée dans chaque dépôt (par ex. `develop/clubs-academies`), **ajoutée d'abord à `deploymentEnabled: false`** (risque R1). Il n'y aura aucun déploiement.

Pour pousser ces branches, il me faudra un accès en écriture aux dépôts : cette session n'a qu'un accès en lecture.

Lots, dans l'ordre demandé :

1. **Création des académies** : demande, validation/refus/suspension, invitation du responsable
2. **Tableau de bord** : compteurs, prochains entraînements/matchs, dernières publications
3. **Gestion des joueurs** : fiches privées, représentants, consentements
4. **Gestion des catégories**
5. **Gestion des entraîneurs** : encadrement, invitations, affectation aux catégories
6. **Gestion des entraînements** : séances, présences
7. **Gestion des matchs**
8. **Gestion des compétitions** : équipes engagées
9. **Résultats et classements** : vue calculée, statistiques filtrées par consentement
10. **Actualités et médias** : posts, photos, YouTube, règle des mineurs
11. **Notifications** : abonnements, déclencheurs (selon D2)
12. **Pages publiques** : liste, page académie, partage WhatsApp
13. **Administration FAMpro** : validation, modération, signalements, journal

Chaque lot comprend la migration, le contrat partagé, l'interface et ses tests. Un lot n'est commencé qu'une fois le précédent vert.

---

## 12. Plan de tests (phase 4)

| Type | Contenu | Outil |
|---|---|---|
| Fonctionnels | Chaque commande RPC (cas nominal, erreurs, idempotence), parcours complet du responsable | PGlite (admin), `node --test` (public) |
| RLS / accès direct | `anon` et `authenticated` : `select`/`insert`/`update`/`delete` directs sur chaque table `koki_sport` → refusés | PostgreSQL local avec les rôles simulés (`simulation-supabase.sql`) |
| **Inter-académies** | Deux académies A et B : un membre de A tente de lire ou modifier joueurs, séances, matchs, médias et membres de B (par identifiant direct, par catégorie de B, par FK croisée) → tout refusé | Idem, matrice générée automatiquement |
| Rôles | Matrice §8.3 testée case par case (entraîneur hors de ses catégories, communication sans accès aux joueurs, membre retiré, académie suspendue) | Idem |
| Mineurs | Sans consentement → invisible ; consentement retiré → masqué immédiatement ; média avec un joueur non autorisé → privé ; aucun champ interdit dans la RPC publique | Idem + inspection des réponses JSON |
| Stockage | Dépôt dans le dossier d'une autre académie refusé ; lecture anonyme d'un média non publié refusée ; type ou taille interdits refusés ; EXIF retiré | Supabase local (Docker) |
| Mobile | Parcours responsable et visiteur à 320/360/390 px, iPhone SE, iPhone 13, Pixel 7, petit Android | Playwright (`tests/e2e`), puis vrais téléphones (`docs/protocole-tests-telephone.md`) |
| **Non-régression** | Suites existantes des deux dépôts (82 + 63 fichiers) ; `verifier.sh` : les 549 éléments de référence restent identiques, seuls les ajouts `koki_sport` diffèrent ; parcours Commerce, Transport et notifications d'un compte professionnel existant inchangés | CI existante |

---

## 13. Ce qui reste interdit sans votre accord

- Toute exécution SQL, migration ou modification de données en production (`qsbmzzbiztfqysstepxm`)
- Toute modification d'utilisateurs, de rôles, de secrets ou de variables Vercel
- Tout déploiement (production ou prévisualisation reliée à la production)
- Tout usage du projet Supabase TEST (décision D9)
- Toute suppression ou remplacement d'un module existant, dont Sports & ASC

**Prochaine étape :** votre validation de ce plan et vos réponses aux décisions D1 à D9. La phase 3 démarrera ensuite, en local et sur branche non déployable.
