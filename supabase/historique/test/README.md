# Reconstruction de la base KOKI CONNECT TEST

Projet visé : **`euvxtwmyoihnutifshay` uniquement**. Jamais la production
(`qsbmzzbiztfqysstepxm`). Chaque étape exige une autorisation distincte du propriétaire.

| Étape | Fichier | Écrit ? | Autorisation |
|---|---|---|---|
| 0. Restaurer le projet (tableau de bord, *Resume project*) | — | oui (Supabase) | **A** |
| 1. Inventaire | `00-inventaire.sql` | non (lecture) | incluse dans A |
| 2. Nettoyage des objets Koki de test | `01-nettoyage.sql` | oui | **B** |
| 3. Préalable : extension pg_cron | `02-prealables.sql` | oui | **C** |
| 4. Référence (37 fichiers) | `03-reference.sql` | oui | **C** |
| 5. Marqueur « KOKI TEST » | `04-marqueur-test.sql` | oui | **C** |
| 6. Empreinte + comparaison | `../outils/empreinte.sql` + `../outils/comparer.py` | non | — |
| 7. Validation technique | `05-validation.sql` | non (essais annulés) | — |

`03-reference.sql` est généré par `../outils/assembler-test.sh` à partir de
`../reference/ordre.txt` ; ne pas le modifier à la main.

## Garde-fous

- `01-nettoyage.sql` et `03-reference.sql` s'arrêtent si la base contient des comptes,
  des fiches, des publications ou des fichiers : la production en contient, ils ne
  peuvent donc pas s'y appliquer. Le paquet des phases 2 à 6 refuse en outre toute
  base marquée « KOKI TEST » (d'où le marqueur posé à la fin).
- Le nettoyage ne touche ni aux comptes Auth, ni aux schémas gérés par Supabase,
  ni au registre des migrations, ni aux crochets Auth de test (`koki_test`,
  `koki_test_signup`). Tout se fait dans une seule transaction.
- Aucune tâche d'envoi de notifications, aucun `pg_net`, aucun secret : rien ne
  peut appeler l'administration de production depuis TEST (`05-validation.sql` le vérifie).

## Répétition locale (18/11/2026)

État TEST simulé (2 migrations d'octobre + marqueur) → inventaire → nettoyage →
référence → marqueur → empreinte : **549 identiques, 0 écart** ; validation : 12/12 OK ;
garde du nettoyage vérifiée (refus dès qu'un compte existe).

## Validation fonctionnelle (à la main, comptes fictifs « TEST », téléphones +999…)

1. Connexion à la base TEST depuis une préversion (`VITE_KOKI_ENV=test`).
2. Création de 5 comptes fictifs : client, chauffeur, commerçant, prestataire, administrateur
   (2FA activée pour l'administrateur).
3. Commerçant : création d'une boutique, envoi en validation ; administrateur : validation.
4. Produits : création avec et sans prix, avec et sans stock, photo (≤ 10 Mo).
5. Stockage : photo visible une fois la boutique publiée, refusée avant.
6. RLS : un client ne voit pas les fiches d'un autre ; un visiteur ne voit que le publié.
7. Notifications : préférences enregistrées ; aucune réception réelle (pas d'envoi en TEST).
8. Contrôle réseau : l'onglet Réseau du navigateur ne montre que `euvxtwmyoihnutifshay`.
