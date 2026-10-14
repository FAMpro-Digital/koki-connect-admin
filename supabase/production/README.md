# Production Koki Connect (qsbmzzbiztfqysstepxm)

| Date | Opération | Résultat |
|---|---|---|
| 13/10/2026 | `education_bibliotheque` (bucket privé `koki-livres`, 4 règles) | Appliquée et vérifiée |
| 14/10/2026 | `refus-motive.sql` (refus motivé obligatoire côté serveur) — lancé par le propriétaire dans l'éditeur SQL | Appliqué et vérifié (corps identique à la version testée, déclencheur actif, fonction non exposée) |
| 14/10/2026 | `refus-motive-complet.sql` (refus motivé : ancienne décision commerçant, inscriptions chauffeurs, refus de fait par suspension ; refus chauffeur sécurisé : auto-décision interdite, révision exigée) — exécuté une seule fois par Claude avec l'autorisation du propriétaire, garde MD5 `525819041eed1710d0dbc44e62721c4d` validée avant exécution | Appliqué et vérifié (empreintes identiques à la répétition locale : `merchant_business` 55222c1a…, `refus_motive` 75a83ac6… ; fonctions non exécutables par anon/authenticated ; déclencheur `koki_refus_motive` actif ; refus chauffeur motivé vérifié par simulation annulée, aucune donnée créée ; une seconde exécution est bloquée par la garde) |
| 13/10/2026 | `koki-production-phases-2-6.sql` (fondation, phase 2, espace commerçant, modernisation Commerces) — lancé par le propriétaire dans l'éditeur SQL | Appliqué et vérifié |

Vérifications après les phases 2 à 6 :
- Empreinte de structure identique à la répétition locale (195 éléments + la fonction interne Supabase `rls_auto_enable`).
- Fiche d'essai « Tg » archivée dans `koki_private.migration_archive` (privée) puis retirée ; publications, administrateur et photos conservés.
- Flux public opérationnel ; `koki_statistics()` refusée aux visiteurs anonymes ; second lancement du paquet refusé par sa garde.
- Contrôle de sécurité Supabase : uniquement des informations attendues (tables privées sans règle d'accès, donc inaccessibles) et la protection des mots de passe compromis, indisponible sur le forfait gratuit.

Régénérer le paquet : `node scripts/prepare-production-phases.mjs` (`--check` pour vérifier qu'il est à jour).
