# Sécurisation GitHub — proposition (NON appliquée)

Constat du 24/11/2026 (API GitHub, lecture seule). Les deux dépôts sont **publics**.

## 1. Rulesets de `main`

| Dépôt | État |
|---|---|
| `koki-connect` | ruleset actif 25622289 : suppression et poussée forcée interdites ; PR obligatoire (0 approbation) ; contrôles `verify`, `e2e`, `lint` obligatoires et à jour ; aucun contournement. **Manquent** : historique linéaire, fusion squash seule, discussions résolues, invalidation des approbations après poussée |
| `koki-connect-admin` | **aucune protection** (ni ruleset, ni protection classique) : une poussée directe sur `main` déclenche un déploiement de production Vercel |

## 2. Rulesets proposés

- `ruleset-koki-connect-admin.json` (PRIORITÉ) : PR obligatoire ; poussées directes, forcées et
  suppression interdites ; historique linéaire ; fusion squash seule ; discussions résolues ;
  approbations invalidées après nouvelle poussée ; contrôles `verify`, `historique-sql`,
  `historique-sql-pg17` obligatoires et à jour ; **aucun contournement**.
- `ruleset-koki-connect-25622289-complet.json` : ruleset du site public complet (règles actuelles
  conservées + historique linéaire, squash seule, discussions résolues, invalidation des approbations).
- 0 approbation requise : un seul mainteneur ; une approbation obligatoire bloquerait toute fusion.
- `foot-essais-reels` reste non bloquant tant que sa stabilité n'est pas établie (dépend d'images Docker
  publiques ; un refus de téléchargement a déjà été observé, puis réessayé avec succès).

**Effet sur `feature/module-football`** : aucun. Les règles ne visent que `refs/heads/main` ; les poussées
et la CI des PR #63 et #144 restent possibles. Seule la fusion vers `main` exigera des contrôles verts.

## 3. GitHub Actions (revue des fichiers de workflow)

| Point | Constat |
|---|---|
| Permissions du jeton | `permissions: contents: read` en tête de **tous** les workflows des deux dépôts |
| Déclencheurs | `pull_request`, `push` (branches listées), `workflow_dispatch` ; **aucun** `pull_request_target` ni `workflow_run` |
| Contributions externes (forks) | `pull_request` exécute le code du fork **sans secrets** et avec un jeton en lecture seule : pas d'exfiltration de secrets possible par ce biais |
| Secrets utilisés | un seul : `KOKI_TEST_ACCOUNTS_JSON` (site public, `performance.yml`), sous l'environnement protégé `koki-performance-test` et une phrase d'autorisation exacte ; le nouveau `foot-essais-heberges.yml` suit le même modèle (`koki-foot-essai`) |
| Actions tierces | épinglées par empreinte (checkout, setup-node, upload-artifact, k6) ; la CLI Supabase est installée par npm à version fixe (2.122.1) |
| Non vérifiable d'ici (API refusée par le proxy) | réglages Actions du dépôt (« Fork pull request workflows », approbation des contributeurs externes, permissions par défaut du jeton), environnements et leurs relecteurs, liste des secrets |
| Sécurité du dépôt | **analyse de secrets, protection des poussées et correctifs Dependabot désactivés** sur les deux dépôts (gratuits pour un dépôt public) |

Recommandations (à appliquer par le propriétaire) :
1. Settings › Actions › General : « Require approval for all external contributors » ; permissions par
   défaut du jeton en lecture seule ; interdire à Actions de créer ou approuver des PR.
2. Settings › Code security : activer *Secret scanning* et *Push protection*, *Dependabot alerts* et
   *security updates*.
3. Créer l'environnement `koki-foot-essai` avec relecteur obligatoire, limité à la branche `main`
   et à `feature/module-football`.

Note : deux fichiers de test contiennent des chaînes **factices** imitant un JWT et une clé `sb_secret_`
(tests d'expurgation). Elles ne sont pas de vrais secrets mais peuvent déclencher une alerte de l'analyse
de secrets ; à marquer « faux positif » le cas échéant.

## 4. Application (après autorisation écrite seulement)

```bash
gh api -X POST repos/FAMpro-Digital/koki-connect-admin/rulesets --input docs/protection-branches/ruleset-koki-connect-admin.json
gh api -X PUT  repos/FAMpro-Digital/koki-connect/rulesets/25622289 --input docs/protection-branches/ruleset-koki-connect-25622289-complet.json
```
Contrôle après application : `gh api repos/FAMpro-Digital/<dépôt>/rules/branches/main`.
