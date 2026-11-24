# Protection des branches `main` — proposition (NON appliquée)

Constat du 24/11/2026 (API GitHub, lecture seule) :

| Dépôt | Visibilité | Protection de `main` |
|---|---|---|
| `FAMpro-Digital/koki-connect` | **public** | ruleset actif 25622289 : suppression et poussée forcée interdites ; PR obligatoire (0 approbation) ; contrôles `verify`, `e2e`, `lint` obligatoires et à jour ; aucun contournement |
| `FAMpro-Digital/koki-connect-admin` | **public** | **aucune** (ni ruleset, ni protection classique) |

Correction du rapport de phase 5 : `koki-connect` était déjà protégé par un ruleset (l'API de protection
« classique » répondait « Branch not protected », ce qui ne couvre pas les rulesets).

## Proposition

- **Admin** : `ruleset-koki-connect-admin.json` — PR obligatoire, poussée directe et forcée interdites,
  suppression interdite, historique linéaire (fusion « squash » seule), contrôles `verify`, `historique-sql`
  et `historique-sql-pg17` obligatoires et à jour, discussions résolues, aucun contournement.
  `foot-essais-reels` reste non bloquant tant qu'il n'a pas prouvé sa stabilité (à rendre obligatoire ensuite).
- **Site public** : `ruleset-koki-connect-complements.json` — ajouter l'historique linéaire et la fusion
  « squash » seule au ruleset existant.
- 0 approbation requise : un seul mainteneur ; une approbation obligatoire bloquerait toute fusion sans
  contournement. À passer à 1 si un second relecteur rejoint le projet.

## Effet sur `feature/module-football`

Les règles visent uniquement `refs/heads/main`. Les poussées sur `feature/module-football`, la CI des PR #63
et #144 et leur mise à jour restent possibles. Seule la fusion vers `main` exigera des contrôles verts.
Vercel : inchangé (production depuis `main`, branche Football bloquée par `vercel.json`).

## Application (après autorisation écrite seulement)

```bash
gh api -X POST repos/FAMpro-Digital/koki-connect-admin/rulesets --input docs/protection-branches/ruleset-koki-connect-admin.json
```
Pour le site public : modifier le ruleset 25622289 dans Settings › Rules › Rulesets (ou `gh api -X PUT
repos/FAMpro-Digital/koki-connect/rulesets/25622289` avec le ruleset complet mis à jour).
