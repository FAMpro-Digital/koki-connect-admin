# Production Koki Connect (qsbmzzbiztfqysstepxm)

| Date | Opération | Résultat |
|---|---|---|
| 13/10/2026 | `education_bibliotheque` (bucket privé `koki-livres`, 4 règles) | Appliquée et vérifiée |
| 13/10/2026 | `koki-production-phases-2-6.sql` (fondation, phase 2, espace commerçant, modernisation Commerces) — lancé par le propriétaire dans l'éditeur SQL | Appliqué et vérifié |

Vérifications après les phases 2 à 6 :
- Empreinte de structure identique à la répétition locale (195 éléments + la fonction interne Supabase `rls_auto_enable`).
- Fiche d'essai « Tg » archivée dans `koki_private.migration_archive` (privée) puis retirée ; publications, administrateur et photos conservés.
- Flux public opérationnel ; `koki_statistics()` refusée aux visiteurs anonymes ; second lancement du paquet refusé par sa garde.
- Contrôle de sécurité Supabase : uniquement des informations attendues (tables privées sans règle d'accès, donc inaccessibles) et la protection des mots de passe compromis, indisponible sur le forfait gratuit.

Régénérer le paquet : `node scripts/prepare-production-phases.mjs` (`--check` pour vérifier qu'il est à jour).
