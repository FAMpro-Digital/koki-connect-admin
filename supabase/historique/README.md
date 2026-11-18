# Historique centralisé des migrations SQL — Koki Connect

Ce dossier est **la source unique** de l'état de la base de production
(`qsbmzzbiztfqysstepxm`). Toute modification de structure passe désormais par
ici, avant d'être appliquée où que ce soit.

Rien dans ce dossier ne s'exécute automatiquement contre Supabase. Les outils
ne travaillent que sur une base PostgreSQL locale et refusent tout hôte distant.

## 1. Référence au 18/11/2026

`reference/ordre.txt` liste, dans l'ordre, les 37 fichiers qui reconstruisent
exactement la structure de production à cette date. Le résultat a été comparé
à une empreinte relevée en production en lecture seule
(`reference/empreinte-production-2026-11-18.txt`) :

**549 éléments identiques, 0 écart** (tables, colonnes, contraintes, index,
règles d'accès RLS, déclencheurs, fonctions, droits, buckets de stockage).

Seuls sont exclus de la comparaison : la fonction interne de la plateforme
`rls_auto_enable` et les tâches planifiées (propres à chaque environnement).

Vérifier à tout moment (base locale uniquement) :

```bash
PGHOST=/tmp PGPORT=5432 bash supabase/historique/outils/verifier.sh
```

La CI exécute la même vérification sur chaque proposition de modification
(tâche `historique-sql`).

## 2. Inventaire : ce qui a été appliqué hors historique

La production compte 28 migrations enregistrées dans
`supabase_migrations.schema_migrations`. Elles **ne suffisent pas** à la
reconstruire. Ont été appliqués à la main (éditeur SQL), sans trace dans ce
registre :

| Élément | Source dans la référence | Remarque |
|---|---|---|
| Phases 2 à 6 (fondation Commerces/Transport, commerçants, modernisation) | `supabase/production/koki-production-phases-2-6.sql` | 125 Ko, le plus gros lot. Appliqué le 13/10 |
| Refus motivé (2 lots) | `supabase/production/refus-motive*.sql` | 14/10 |
| Sécurité et suivi Transport | `supabase/production/transport-securite-suivi.sql` | 14/10 |
| Statut des signalements Transport | `supabase/production/signalements-statut.sql` | 14/10 |
| Modération des publications | `supabase/proposals/publication-moderation.sql` | Pas d'entrée à ce nom |
| Table `koki_content_images` | `reference/sources/rattrapage_01_content_images.sql` | **Aucun fichier source n'existait** ; définition relevée en production |
| Version actuelle de `koki_account_delete` | `reference/sources/rattrapage_02_account_delete.sql` | Différente de la migration enregistrée le 17/11 |
| Droits d'accès (tables, colonnes, fonctions, schémas) | `reference/sources/rattrapage_99_droits.sql` | Retouchés à plusieurs reprises ; relevés en production |
| Tâche planifiée `koki-notifications-dispatch` + secret du coffre | — (volontairement absent) | Appelle l'API d'administration de production : **ne doit jamais exister en test** |
| Données : localité Coki → Koki (18/11) | `supabase/production/2026-11-18-localite-koki.sql` | Données, pas structure |

Les 9 migrations enregistrées en production mais absentes des dépôts sont
reprises telles quelles depuis le registre : `reference/sources/prod_*.sql`.
Les deux scripts venus du site public sont copiés en
`reference/sources/public_*.sql`.

## 3. Règle pour toute nouvelle modification

1. Créer `migrations/AAAAMMJJHHMMSS_nom.sql` **et** son retour arrière
   `retour/AAAAMMJJHHMMSS_nom.sql` (même nom).
2. La migration commence par une **garde** : elle vérifie l'état attendu
   (empreinte d'une fonction, absence d'une table…) et s'arrête sinon, pour
   ne jamais s'appliquer deux fois ni sur une base inattendue.
3. Ajouter la ligne au bas de `reference/ordre.txt` (après les fichiers de
   référence) et lancer `outils/verifier.sh` en local.
4. Appliquer d'abord sur la **base de test**, vérifier, puis — **seulement
   après l'accord explicite du propriétaire** — sur la production.
5. Après application en production : relever une nouvelle empreinte en
   lecture seule, la versionner, et noter l'opération dans
   `supabase/production/README.md` (date, garde, résultat).

## 4. Retour arrière

- **Nouvelle migration** : exécuter son fichier `retour/` correspondant, puis
  revérifier l'empreinte.
- **Problème grave** : la sauvegarde quotidienne de Supabase (forfait
  gratuit : pas de restauration à un instant précis) ; à défaut, rejouer la
  référence sur un projet neuf puis réimporter les données exportées.
- Avant toute intervention en production : exporter les tables touchées
  (`copy … to stdout` en lecture seule) et conserver l'export avec la date.

## 5. Ce qui n'est **pas** encore fait (attend l'accord du propriétaire)

- Enregistrer cette référence dans le registre de production
  (`supabase_migrations.schema_migrations`) : c'est une écriture en
  production.
- Créer la base de test Supabase (choix du projet à faire).
