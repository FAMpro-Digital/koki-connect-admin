# Module Football — intégration API-Football

État : **intégré dans le code et testé en local, NON déployé, rien de modifié en production.**
L'activation demande une validation distincte du propriétaire (§ 6).

## 1. Architecture (aucune nouvelle infrastructure)

Même chemin que les notifications déjà en production (`koki-notifications-dispatch`) :

```
pg_cron (chaque minute, projet Supabase existant)
  └─ pg_net → POST https://koki-connect-admin.vercel.app/api/foot-sync   (secret partagé, lu dans Vault)
       └─ planificateur de quota (server/foot/synchronisation.js)
            ├─ API-Football v3 (server/foot/api-football.js) — clé dans Vercel uniquement
            └─ public.koki_foot_sync('importer' | 'erreur')   — clé service, serveur uniquement
```

- **La clé API-Football n'existe que dans les variables serveur de Vercel.** Elle n'est ni dans le dépôt,
  ni dans le navigateur (aucun préfixe `VITE_`), ni dans les réponses ou journaux (expurgée, testé).
  Un test vérifie qu'aucun fichier du navigateur n'importe le connecteur.
- **Toutes les écritures passent par `koki_foot_sync`** : verrous manuels (global ou par champ), conflits
  API ↔ correction, journal des synchronisations, pause progressive après erreur, fraîcheur. Rien n'est contourné.
- **Les saisies manuelles restent possibles** : les matchs `manuel` ne sont jamais touchés par l'import ;
  une correction sur un match `api` pose un verrou et toute divergence ultérieure ouvre un conflit.
- Les logos du fournisseur ne sont pas importés (CSP inchangée ; pastille aux initiales, voir mise en production § 5).

## 2. Ce qui est synchronisé

| Donnée | Requête | Fréquence (formule gratuite) |
|---|---|---|
| Calendrier et résultats | `fixtures?league&season` | 2 fois par jour par compétition |
| Classement | `standings?league&season` | 1 fois par jour + après chaque match terminé |
| Scores en direct, statut, minute | `fixtures?ids=` (20 matchs par requête) | intervalle calculé sur le quota (≈ 90 s pour un créneau de match) |
| Événements (buts, c.s.c., penalties, cartons, remplacements, tirs au but) | inclus dans `fixtures?ids=` | avec le direct ; un but annulé disparaît |
| Prolongation, tirs au but | `score.extratime`, `score.penalty` | avec le direct |

Seules les compétitions **publiées et actives** sont suivies. Une compétition est d'abord **découverte**
(créée NON publiée), puis publiée par un administrateur dans l'admin (Sport › Football) : rien ne s'affiche
et aucune requête n'est dépensée sans cette décision.

## 3. Quota : règles du planificateur

- Quota du jour lu dans les en-têtes du fournisseur (`x-ratelimit-requests-remaining`), remis à zéro à 00:00 UTC.
- Réserve de 10 requêtes gardée pour la vérification et la découverte manuelles.
- Les besoins du jour (calendrier, classements, classement final) sont réservés avant le direct ; le reste
  est réparti sur les minutes de match restantes de la journée (réunion des créneaux de 130 min).
- Au plus 9 requêtes par passage (plafond gratuit : 10 par minute).
- Quota épuisé ou dépassé : erreur journalisée, **pause jusqu'à 00:00 UTC**, plus aucune requête ; les matchs
  en jeu passent en « ancien » à l'affichage (données périmées signalées, jamais présentées comme à jour).
- Clé refusée : pause 24 h. Fournisseur indisponible ou délai dépassé : pause progressive 1, 2, 4… 60 min.
- Requête groupée refusée par la formule : repli match par match (2 au plus).

## 4. Formule gratuite : limites vérifiées (sources : api-football.com, novembre 2026)

- **100 requêtes par jour**, **10 par minute**, tous les points d'accès et toutes les compétitions.
- **Saisons limitées à « année − 4 » à « année − 2 » : 2022, 2023 et 2024 en 2026.** La saison en cours
  (2025/26 au Sénégal) n'est **pas accessible** : la formule gratuite permet de tester toute la chaîne sur des
  données réelles **passées** (saison 2024 = 2024/25), mais **pas** d'afficher les scores en direct ni le
  calendrier de la saison actuelle.
- Formule Pro (payante, non souscrite) : 7 500 requêtes par jour, 300 par minute, saison en cours.
  Le planificateur s'adapte seul : `API_FOOTBALL_LIMITE_JOUR=7500`, `API_FOOTBALL_PAR_MINUTE=300`.

## 5. Paramètres pour connecter le compte API-Football

À créer dans **Vercel › koki-connect-admin › Settings › Environment Variables › Production**,
type **Secret** pour les deux premiers :

| Variable | Valeur |
|---|---|
| `API_FOOTBALL_KEY` | clé du tableau de bord **dashboard.api-football.com** (compte direct API-Sports, en-tête `x-apisports-key`). Une clé RapidAPI ne fonctionne **pas** avec ce connecteur. |
| `FOOT_SYNC_SECRET` | secret aléatoire d'au moins 32 caractères (même valeur que le secret Vault ci-dessous) |
| `FOOT_SYNC_ENABLED` | `false` pendant l'installation, `true` pour démarrer (interrupteur d'arrêt immédiat) |
| `API_FOOTBALL_LIMITE_JOUR` | `100` (gratuit) |
| `API_FOOTBALL_RESERVE` | `10` |
| `API_FOOTBALL_PAR_MINUTE` | `10` (gratuit) |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | déjà utilisées par les notifications (à confirmer présentes) |

Dans Supabase (SQL, projet existant) : `select vault.create_secret('<FOOT_SYNC_SECRET>','koki_foot_sync_secret','Appel de /api/foot-sync');`

## 6. Activation (chaque étape soumise à validation)

1. Fusion de la PR (déploie le code de l'admin ; inactif tant que `FOOT_SYNC_ENABLED` ≠ `true`).
2. Variables Vercel (§ 5) puis redéploiement.
3. **Vérification réelle de la couverture** (1 requête, aucune écriture) :
   `POST /api/foot-sync {"mode":"verifier","pays":"Senegal"}` — ou en local
   `API_FOOTBALL_KEY=… node scripts/api-football-verifier.mjs Senegal`.
   Elle donne les identifiants réels de la Ligue 1 et de la Ligue 2 et, pour chaque saison, la disponibilité
   des événements et du classement. **Aucune compétition n'est activée si elle n'apparaît pas ici.**
4. Proposition `20261201000800` (fonction de lecture du planning, ajout seul).
5. Découverte d'une compétition vérifiée : `{"mode":"decouvrir","ligue":<id>,"saison":2024}` (2 à 3 requêtes) ;
   elle est créée **non publiée** ; contrôle dans l'admin, puis publication.
6. Secret Vault, puis proposition `20261201000810` (tâche pg_cron chaque minute), puis `FOOT_SYNC_ENABLED=true`.

Retour arrière : `FOOT_SYNC_ENABLED=false` (immédiat), `retour-20261201000810`, `retour-20261201000800`.
Les données importées restent ; une compétition se masque en la dépubliant.

## 7. Tests

- `tests/foot-api-football.test.js` (18 tests) : statuts, scores (prolongation, tirs au but), événements et clés
  stables, classement, couverture, erreurs « 200 + errors », quota et intervalle du direct, repli, clé jamais
  renvoyée, fonction serveur (secret, interrupteur, garde d'environnement), isolement du navigateur.
- `supabase/historique/outils/tester-foot-api.sh` (CI, PostgreSQL 16 et 17) : connecteur avec la **vraie**
  `koki_foot_sync` en base locale et un fournisseur simulé — découverte non publiée, aucune requête sans
  publication, direct, but annulé retiré, verrou conservé et conflits ouverts, classement final, quota dépassé
  → pause et données « anciennes » ; propositions 0800/0810 : gardes, application, retours.
- **Non réalisé** : aucun appel réel à API-Football (clé non fournie). La couverture du Sénégal reste à
  confirmer avec l'étape 3.
