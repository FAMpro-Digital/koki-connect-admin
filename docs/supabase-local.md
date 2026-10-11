# Supabase local (gratuit, sur votre ordinateur)

Environnement de développement complet sans projet en ligne : base PostgreSQL 17, Auth, Storage, Studio et boîte e-mail de test, dans Docker. **Aucune base en ligne n'est touchée.** Le projet Supabase TEST en ligne reste réservé à la future préproduction.

## Ce que contient la branche `dev/supabase-local`

| Fichier | Rôle |
|---|---|
| `supabase/config.toml` | Configuration locale : ports 54321–54324, PostgreSQL 17, SMS en mode test, MFA TOTP, e-mails capturés |
| `supabase/migrations/` | Copies **générées** de `schema.sql` + les 3 propositions, précédées de la garde « projet vide » et suivies du marqueur `KOKI TEST` |
| `scripts/build-local-migrations.mjs` | Régénère les migrations (`npm run supabase:migrations`) ; `--check` vérifie qu'elles sont à jour |
| `supabase/seed.sql` | Données fictives `TEST` (comptes, commerce, service, chauffeur, tarifs, contenus de toutes les rubriques) |
| `.env.supabase-local.example` | Modèle de configuration de l'administration en mode local (sans secret) |
| `src/backend-guard.js` | Garde-fou : base locale seulement avec `npm run dev:local`, jamais dans une version publiée |

Les sources restent `supabase/schema.sql` et `supabase/proposals/*.sql`. Après toute modification de ces fichiers : `npm run supabase:migrations`.

## Installation (une fois, sur Mac)

1. Docker : [Docker Desktop](https://www.docker.com/products/docker-desktop/) ou, plus léger et gratuit, `brew install colima docker && colima start`.
2. CLI Supabase (version récente) : `brew install supabase/tap/supabase`.
3. Node.js 24, puis `npm ci` dans le dossier de l'administration.

## Démarrer

Dans le dossier **koki-connect-admin** :

```bash
supabase start            # 1er lancement : télécharge les images Docker (quelques minutes)
supabase status           # affiche les adresses et la clé « Publishable »
cp .env.supabase-local.example .env.supabase-local
npm run dev:local         # administration : http://127.0.0.1:5173 (bandeau « BASE LOCALE »)
```

Dans le dossier **koki-connect** (site public) :

```bash
cp .env.supabase-local.example .env.supabase-local   # facultatif : valeurs par défaut identiques
node scripts/serve-local.mjs                           # site public : http://127.0.0.1:8080
```

Outils : Studio http://127.0.0.1:54323 · e-mails de test (Mailpit) http://127.0.0.1:54324.

## Comptes fictifs

| Compte | Connexion |
|---|---|
| TEST Administrateur `koki-test-admin@example.test` (superadmin) | Écran de connexion → « Activer mon compte / mot de passe oublié » → ouvrir l'e-mail dans Mailpit → choisir un mot de passe → enrôler la double authentification (application TOTP) |
| TEST Client | SMS `+999000000001`, code `123456` |
| TEST Chauffeur (Taxi disponible à 15,56 / −16,21) | SMS `+999000000002`, code `123456` |
| TEST Commerçant (TEST Boutique Koki, 2 produits) | SMS `+999000000003`, code `123456` |
| TEST Prestataire (TEST Plomberie) | SMS `+999000000004`, code `123456` |

Aucun mot de passe n'est enregistré dans le dépôt. Pour tout autre numéro (ex. `77 123 45 67`), le code n'est **pas envoyé** : il apparaît dans Studio, table `koki_local.sms_codes`. Aucun fournisseur SMS n'est configuré, donc aucun SMS réel ne peut partir.

## Repartir de zéro

```bash
supabase db reset         # recrée la base locale : migrations + données fictives
supabase stop             # arrête Docker (les données locales sont conservées)
```

## Protections

- **Ne jamais lancer** `supabase link`, `supabase db push` ni `supabase login` depuis ce dépôt. En cas d'erreur, la première migration refuse de s'exécuter sur une base déjà installée (comme la production) : « Projet non vide : installation refusée ».
- `seed.sql` refuse de s'exécuter sur une base sans le marqueur `KOKI TEST`.
- L'administration n'accepte `http://127.0.0.1:54321` qu'avec `npm run dev:local` ; une version publiée (`npm run build`) refuse toute adresse locale. En mode local, toute adresse distante est refusée.
- Le site public n'accepte le Supabase local que si la page est servie depuis `127.0.0.1`/`localhost` **et** que la configuration servie par `scripts/serve-local.mjs` est marquée `local`. Les fichiers publiés (`backend.json`, `config.json` à `enabled:false`) ne changent pas ; `scripts/prepare-preview.mjs` refuse une configuration locale.
- `.env.supabase-local` est ignoré par Git. Les clés « Publishable » locales sont publiques et identiques sur toutes les installations ; aucune clé secrète n'est utilisée.

Tests : `tests/supabase-local.test.js` rejoue les migrations et les données fictives, vérifie le flux public, une commande métier, le crochet SMS, les gardes-fous et l'absence de secrets.
