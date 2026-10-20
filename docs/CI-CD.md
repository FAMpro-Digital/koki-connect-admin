# CI/CD de Koki Connect Admin

## Workflows GitHub Actions

| Fichier | Déclenchement | Rôle |
|---|---|---|
| `.github/workflows/ci.yml` | Pull Request vers `main`, push sur `main`, lancement manuel | Contrôle `verify` : installation verrouillée (`npm ci`), garde de configuration (CSP sans `unsafe-inline`), migrations locales à jour, `npm test`, `npm run build` |
| `.github/workflows/development.yml` | Push et PR sur `develop/phases-2-6` | Inchangé (branche de développement historique) |

Permissions : `contents: read` uniquement. Les actions sont épinglées par empreinte de commit.
Tests et build s'exécutent sans accès réseau (`unshare --net`) avec un utilisateur non privilégié, comme avant.

## Exiger `verify` avant toute fusion (à faire une fois, dans GitHub)

Le jeton GitHub de l'automatisation ne permet pas de lire ni de créer les règles de protection : cette étape est manuelle.

Méthode rapide (jeu de règles prêt à importer) :
1. Dépôt → **Settings** → **Rules** → **Rulesets** → **New ruleset** → **Import a ruleset**.
2. Choisir `.github/rulesets/protect-main.json`.
3. Vérifier puis **Create**. Le jeu de règles : PR obligatoire, contrôle `verify` obligatoire et à jour, pas de force-push, pas de suppression de `main`. Aucun contournement (même pour le propriétaire).

Important : `verify` n'apparaît dans la liste des contrôles qu'après une première exécution de `ci.yml` (ouvrir une PR vers `main` suffit).

## Déploiements Vercel

- `vercel.json` contient les en-têtes de sécurité et la liste `git.deploymentEnabled` des branches de travail dont l'aperçu automatique est désactivé.
- Toute nouvelle branche doit y être ajoutée (valeur `false`) dans son premier commit.
- À vérifier dans Vercel (non lisible par l'automatisation) : **Settings → Git → Production Branch** = `main`.
- Production Supabase : aucune migration n'est appliquée automatiquement. Voir `supabase/production/README.md`.
