# Tests de charge (k6)

**Jamais contre la production.** Le script `garde.js` refuse la référence de production `qsbmzzbiztfqysstepxm` et tout hôte distant non déclaré comme environnement de TEST.

## Prérequis
- [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/)
- Supabase **local** (`supabase start`, Docker) avec les migrations locales (`npm run supabase:migrations`) et `supabase/seed.sql`
- Clé publishable locale (affichée par `supabase status`) : jamais une clé `service_role` ou secrète

## Lancer
```bash
BASE_URL=http://127.0.0.1:54321 ANON_KEY=sb_publishable_... ./loadtests/run-paliers.sh
```
Paliers : 10, 50, 100, 250, 500 utilisateurs virtuels (30 s de montée, 2 min tenues, 20 s de descente). L'essai s'arrête dès que l'un des seuils est franchi : erreurs ≥ 5 % ou p95 ≥ 2 s. Les paliers suivants ne sont alors pas lancés. Résumés JSON dans `loadtests/resultats/` (ignoré par git).

## Ce qui est mesuré
Flux public complet (`koki_public_feed`) et paginé (`koki_public_feed_page`, si installée). Un Supabase local n'est **pas** représentatif du forfait hébergé (CPU, pooler, limites de requêtes) : les chiffres servent à comparer avant/après un changement, pas à dimensionner la production.

## Un environnement hébergé de test ?
Seulement un projet Supabase **dédié au test** (jamais le projet de production), en déclarant `KOKI_ENV=TEST` et `KOKI_HOTE_TEST=<réf>.supabase.co`. Vérifier d'abord les limites du forfait : un test de charge peut épuiser le quota de requêtes ou être limité par le fournisseur.
