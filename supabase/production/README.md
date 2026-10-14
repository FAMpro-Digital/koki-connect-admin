# Production Koki Connect (qsbmzzbiztfqysstepxm)

| Date | Opération | Résultat |
|---|---|---|
| 13/10/2026 | `education_bibliotheque` (bucket privé `koki-livres`, 4 règles) | Appliquée et vérifiée |
| 14/10/2026 | `refus-motive.sql` (refus motivé obligatoire côté serveur) — lancé par le propriétaire dans l'éditeur SQL | Appliqué et vérifié (corps identique à la version testée, déclencheur actif, fonction non exposée) |
| 14/10/2026 | `refus-motive-complet.sql` (refus motivé : ancienne décision commerçant, inscriptions chauffeurs, refus de fait par suspension ; refus chauffeur sécurisé : auto-décision interdite, révision exigée) — exécuté une seule fois par Claude avec l'autorisation du propriétaire, garde MD5 `525819041eed1710d0dbc44e62721c4d` validée avant exécution | Appliqué et vérifié (empreintes identiques à la répétition locale : `merchant_business` 55222c1a…, `refus_motive` 75a83ac6… ; fonctions non exécutables par anon/authenticated ; déclencheur `koki_refus_motive` actif ; refus chauffeur motivé vérifié par simulation annulée, aucune donnée créée ; une seconde exécution est bloquée par la garde) |
| 14/10/2026 | `transport-securite-suivi.sql` (code de départ, demandes expirées après 2 min, suivi en direct, note, signalement, tableau du chauffeur) — exécuté une seule fois par Claude avec l'autorisation du propriétaire, garde validée (`public.koki_business` 1cc5c9ca…, rien d'installé) | Appliqué et vérifié (empreintes identiques à la répétition locale : `koki_business` ed14f4a6…, `transport_plus` a1c40400… ; 2 déclencheurs actifs ; tables privées sans accès direct ; parcours complet vérifié par simulation annulée, aucune donnée créée). Aucun tarif publié à cette date : à fixer dans l'administration |
| 14/10/2026 | `signalements-statut.sql` (traitement des signalements Transport : statut Nouveau / En cours / Traité, note de l'administration, journal) — exécuté une seule fois par Claude avec l'autorisation du propriétaire, garde validée (`public.koki_business` ed14f4a6…, rien d'installé) | Appliqué et vérifié (empreintes identiques au fichier : `koki_business` 2828adcb…, `ride_reports_admin` 2043a5d8… ; `transport_plus` inchangé a1c40400… ; 3 colonnes ajoutées ; table privée sans accès direct ; catalogue anonyme et refus anonyme des commandes d'administration vérifiés par transactions annulées). 0 signalement existant, aucune donnée modifiée |
| 13/10/2026 | `koki-production-phases-2-6.sql` (fondation, phase 2, espace commerçant, modernisation Commerces) — lancé par le propriétaire dans l'éditeur SQL | Appliqué et vérifié |

Vérifications après les phases 2 à 6 :
- Empreinte de structure identique à la répétition locale (195 éléments + la fonction interne Supabase `rls_auto_enable`).
- Fiche d'essai « Tg » archivée dans `koki_private.migration_archive` (privée) puis retirée ; publications, administrateur et photos conservés.
- Flux public opérationnel ; `koki_statistics()` refusée aux visiteurs anonymes ; second lancement du paquet refusé par sa garde.
- Contrôle de sécurité Supabase : uniquement des informations attendues (tables privées sans règle d'accès, donc inaccessibles) et la protection des mots de passe compromis, indisponible sur le forfait gratuit.

Régénérer le paquet : `node scripts/prepare-production-phases.mjs` (`--check` pour vérifier qu'il est à jour).
