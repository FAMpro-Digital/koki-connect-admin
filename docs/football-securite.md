# Module Football — sécurité, privilèges et limites du journal

Document de la branche `feature/module-football` (PR #63). Migrations **non appliquées en production**.
Les éléments de ce document sont vérifiés par `supabase/tests/foot.sql` (sections 1, 15, 24 et 25),
exécuté par `bash supabase/historique/outils/tester-foot.sh` sur une copie locale de la structure de
production.

## 1. Principe

- Toutes les données du module sont dans le schéma privé `koki_foot`.
- Aucun rôle applicatif (`anon`, `authenticated`, `service_role`) n'a de droit sur ce schéma, ses
  tables, ses séquences ni ses fonctions internes.
- RLS est activée sur chaque table, **sans aucune politique** : tout est refusé par défaut, même si
  un droit était accordé par erreur un jour.
- Le seul accès passe par trois fonctions publiques `SECURITY DEFINER`. Chacune vérifie l'appelant
  et refuse tout champ d'entrée inattendu.

## 2. Points d'entrée et droits d'exécution

| Fonction | Exécutable par | Contrôle interne |
|---|---|---|
| `public.koki_foot_public(text,jsonb)` | anon, authenticated | Lecture seule des compétitions publiées ; entrée limitée à 8 Ko |
| `public.koki_foot_admin(text,jsonb)` | authenticated | `koki_private.allowed()` : `read` pour lire, `content` (editor ou superadmin) pour écrire, `superadmin` pour régler les seuils ; session `aal2` (double authentification) obligatoire |
| `public.koki_foot_sync(text,jsonb)` | service_role | Vérifie en plus `auth.role() = 'service_role'` ; une seule synchronisation à la fois par fournisseur |

Les tests vérifient qu'un utilisateur `authenticated` qui présente un faux jeton `service_role` ne
peut pas appeler `koki_foot_sync`. Ils vérifient aussi qu'un superadmin ne le peut pas davantage, et
que `service_role` ne peut ni appeler `koki_foot_admin` ni écrire directement dans les tables.

## 3. Fonctions SECURITY DEFINER (relevé sur la base de test)

| Fonction | Exécutable par |
|---|---|
| `koki_foot.appliquer_score(...)` | aucun |
| `koki_foot.corriger(...)` | aucun |
| `koki_foot.diffuser(text,jsonb)` | aucun |
| `koki_foot.evenement_diffuse()` (déclencheur) | aucun |
| `koki_foot.exiger(text)` | aucun |
| `koki_foot.horaire_change()` (déclencheur) | aucun |
| `koki_foot.match_diffuse()` (déclencheur) | aucun |
| `koki_foot.signaler_conflit(...)` | aucun |
| `koki_foot.verrouiller(...)` | aucun |
| `public.koki_foot_admin(text,jsonb)` | authenticated |
| `public.koki_foot_public(text,jsonb)` | anon, authenticated |
| `public.koki_foot_sync(text,jsonb)` | service_role |

Toutes ont `search_path=''` : chaque objet est nommé avec son schéma, ce qui empêche le
détournement par un objet homonyme. Un test échoue si une nouvelle fonction SECURITY DEFINER est
créée sans ce réglage, ou si une fonction interne devient exécutable par un rôle applicatif.

## 4. Données diffusées publiquement

- Canal Realtime Broadcast **public** `koki-foot`. Il transmet uniquement l'identifiant du match,
  sa révision, son statut, la minute, les scores et la date. Aucun nom de joueur, motif, auteur ni
  courriel (vérifié par un test).
- Lecture publique : seuls les matchs publiés de compétitions publiées sont visibles.
- `sources` expose trois champs par fournisseur (fournisseur, dernière actualisation, état), sans
  clé, quota ni message d'erreur.
- Les clés des fournisseurs ne sont jamais en base : elles iront dans les variables
  d'environnement de la fonction serveur Vercel (portée Production seulement pour la production).

## 5. Journal des corrections : garanties et LIMITES

### Ce qui est garanti
- Seul un ajout est possible. Un déclencheur refuse `UPDATE` et `DELETE`, et un autre refuse
  `TRUNCATE`. Cela vaut aussi pour le propriétaire du schéma, tant que les déclencheurs sont actifs.
- Aucun rôle applicatif ne peut lire ni écrire le journal directement.
- **Chaînage** : chaque ligne porte `empreinte = SHA-256(empreinte précédente | contenu)`.
  `koki_foot.verifier_journal()`, exposée à l'administration par la commande `verifier_journal`,
  renvoie la première ligne altérée, supprimée ou réordonnée.

### Ce qui n'est PAS garanti
Le **propriétaire des objets** (`postgres` sur Supabase) et tout **superutilisateur** peuvent :
- désactiver les déclencheurs (`ALTER TABLE … DISABLE TRIGGER`), ou passer
  `session_replication_role = replica`, puis modifier ou supprimer des lignes ;
- supprimer la table ou le schéma entier (`DROP`) ;
- **recalculer toute la chaîne** après une altération, en réécrivant toutes les empreintes
  suivantes. Le chaînage rend une altération *détectable* ; il ne l'*empêche* pas face à quelqu'un
  qui contrôle la base.

Les tests le démontrent : avec les déclencheurs désactivés, une modification et une suppression
réussissent, et `verifier_journal()` les signale.

### Mesures recommandées (hors base, à décider)
1. **Ancrage externe** : exporter régulièrement la dernière empreinte (par exemple chaque jour)
   vers un emplacement que le compte Supabase ne peut pas modifier (stockage en écriture seule,
   courriel, dépôt Git signé). Une chaîne recalculée ne correspondra plus à l'ancre.
2. Limiter le nombre de personnes ayant accès au tableau de bord Supabase et au mot de passe
   `postgres`, avec la double authentification sur ces comptes.
3. Envisager l'extension `pgaudit` pour journaliser les instructions DDL (`ALTER TABLE`,
   `DISABLE TRIGGER`, `DROP`) hors du schéma applicatif.
4. Faire vérifier le journal (`verifier_journal`) par l'administration à intervalles réguliers.

## 6. Autres limites connues

- `koki_audit` (journal existant de la plateforme) enregistre la révision et le statut, pas le
  contenu ; le détail des corrections est dans `koki_foot.corrections`.
- Les réglages Realtime du projet Supabase (autorisation des canaux publics) n'ont pas pu être
  vérifiés sans accès à la production.
- `koki_foot.historique_programmation` et `koki_foot.changements_horaire` ne sont pas
  inaltérables : ce sont un historique et une file de travail, pas un journal d'audit. Les
  corrections de programmation sont, elles, aussi inscrites dans le journal chaîné.
