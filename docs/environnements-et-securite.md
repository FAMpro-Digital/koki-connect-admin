# Environnements et sécurité — Koki Connect (étape 1)

Préparé le 18/11/2026. **Aucun paramètre n'a été modifié** : ce document décrit
la configuration cible et les étapes, à appliquer seulement après accord.

## 1. Les trois environnements

| | Développement local | Test / préproduction | Production |
|---|---|---|---|
| Base | PostgreSQL ou Supabase local (`127.0.0.1:54321`), données fictives | Projet Supabase TEST `euvxtwmyoihnutifshay` (organisation « kokiconnect221-ux's Org », compte distinct) | `qsbmzzbiztfqysstepxm` (organisation FAMpro Évents) |
| Site public | `scripts/serve-local.mjs` (configuration remplacée en mémoire, jamais écrite) | `KOKI_ENV=test node scripts/prepare-preview.mjs` → copie `dist/` visant la base de test | Fichiers du dépôt (`assets/portail/backend.json`) — inchangés |
| Administration (navigateur) | `npm run dev:local` | Vercel *Preview* : `VITE_KOKI_ENV=test` + URL et clé publishable de test | Vercel *Production* : `VITE_KOKI_ENV=production` + URL et clé de production |
| Administration (serveur `api/`) | — | `KOKI_ENV=test`, `SUPABASE_URL` de test, clé de service **de test** | `SUPABASE_URL` et clé de service de production, **portée Production uniquement** |
| Tâches planifiées | aucune | `koki-notify-contents` seulement ; **jamais** `koki-notifications-dispatch` | les deux, inchangées |

## 2. Garde-fous en place (code, branches `etape1/separation-environnements`)

- **Site public** : en mode `KOKI_ENV=test`, la copie publiable refuse toute adresse
  de production ou de FAMpro Évents, refuse une clé secrète, et vérifie qu'aucune
  référence de production ne subsiste (configuration et politique de sécurité).
  Tests : `tests/environnements.test.cjs`.
- **Administration** : `src/environment-guard.js`. Environnement lu dans
  `VITE_KOKI_ENV` / `KOKI_ENV`, sinon déduit de Vercel (*preview* → test).
  - test ou local + base de production → l'application refuse de démarrer ;
  - production + autre base que la production → refus ;
  - les deux fonctions serveur (invitations, envoi des notifications) répondent
    503 **avant** toute connexion si la base ne correspond pas à l'environnement.
  - Sans environnement déclaré (cas actuel de la production si la variable
    automatique Vercel n'est pas exposée) : comportement inchangé.
  Tests : `tests/environment-guard.test.js`.
- **Tests automatiques** : déjà isolés (Supabase simulé, références de production
  interdites dans les tests de bout en bout).
- **Historique SQL** : l'outil de vérification refuse tout hôte non local.

## 3. Réglages Vercel à faire (après accord)

Je n'ai pas accès aux projets Vercel depuis cette session : vérifier dans le
tableau de bord, pour chaque variable, la case *Production* / *Preview* / *Development*.

1. `SUPABASE_SERVICE_ROLE_KEY`, `NOTIFICATION_DISPATCH_SECRET`, clés VAPID et
   Twilio de production : **Production uniquement** (pas *Preview*).
2. Ajouter en *Production* : `VITE_KOKI_ENV=production`.
3. Ajouter en *Preview* : `VITE_KOKI_ENV=test`, `KOKI_ENV=test` et les valeurs
   du projet TEST (URL, clé publishable, clé de service de test).
4. Les branches restent non déployables (`git.deploymentEnabled`) tant que la
   base de test n'est pas prête.

Conséquence : aucune. Le site en ligne et l'administration de production ne
changent pas de base ; seules les préversions sont redirigées vers le test.

## 4. Sécurité

### Protection contre les mots de passe divulgués
- Vérifié dans la documentation Supabase : **disponible à partir du forfait Pro**
  (25 $/mois par organisation, hors dépassements). Impossible sur le forfait
  gratuit actuel.
- Étapes, si le passage au Pro est décidé : *Authentication → Providers → Email*,
  cocher « Prevent use of leaked passwords » ; en profiter pour fixer une longueur
  minimale de 10 caractères avec chiffres et lettres.
- Conséquence : seuls les **nouveaux** mots de passe (inscription, changement)
  sont contrôlés ; les comptes existants ne sont pas bloqués.
- Mesure gratuite immédiate possible : longueur minimale et caractères exigés
  (même écran), applicable sans changer de forfait.

### Double authentification (2FA)
- **Administration Koki Connect** : déjà exigée côté serveur. La fonction
  `koki_private.allowed` n'accorde aucun droit sans session `aal2` (code TOTP).
  État au 18/11 : 2 administrateurs actifs, **1 seul a activé sa 2FA** ;
  le second ne peut rien faire dans l'administration tant qu'il ne l'a pas activée.
- **Comptes d'hébergement** (Supabase, Vercel, GitHub, Apple, Google) : activer
  la 2FA de chaque compte dans ses paramètres personnels. Gratuit. C'est la
  protection la plus importante : ces comptes donnent accès à tout.
- 2FA par SMS : module payant chez Supabase, non recommandé (le TOTP suffit).

## 5. Coûts

| Élément | Coût |
|---|---|
| Projet TEST existant (compte et organisation distincts) | 0 € (forfait gratuit) |
| Garde-fous, historique SQL, CI | 0 € |
| Protection des mots de passe divulgués | Forfait Pro : 25 $/mois |
| 2FA TOTP (administration, comptes) | 0 € |
