# Préproduction TEST — phase 6 (installation, retour arrière, Auth)

Projet cible **unique** : Supabase `euvxtwmyoihnutifshay` (« Koki Connect TEST — Préproduction », organisation « kokiconnect221-ux's Org », eu-west-2, gratuit).
Jamais `qsbmzzbiztfqysstepxm` (production, organisation FAMpro Évents) ni `paegdthtusbwxuarhacb`.
Rien de ce dossier n'a été exécuté à distance : chaque étape exige une autorisation explicite.

## État vérifié (lecture seule, 11/10/2026)

`schema.sql` + `proposals/commerce-transport-foundation.sql` installés, base vide (0 compte, 0 fiche, 0 photo), aucune alerte de sécurité.
L'empreinte du projet (`supabase/preproduction/empreinte.sql`) est identique à celle d'une copie locale de la branche pour toutes les fonctions, colonnes, contraintes, index, politiques et déclencheurs Koki. Seuls diffèrent les droits propres à Supabase hébergé (rôles `postgres`, `service_role`, privilège `MAINTAIN` de PostgreSQL 17) et les déclencheurs internes de Storage, que ni le paquet ni le retour arrière ne touchent.

## Fichiers

| Fichier | Rôle |
|---|---|
| `scripts/prepare-test-continuation.mjs` | Génère le paquet, son manifeste et le retour arrière (aucune connexion distante) |
| `supabase/preproduction/koki-test-poursuite-phase6.sql` | Poursuite : phase 2, profils commerçants, Commerces & Services, marqueur « KOKI TEST » — une transaction gardée |
| `…/koki-test-poursuite-phase6.manifest.json` | Cible, références interdites, empreintes SHA-256 des sources et du paquet |
| `…/retour-arriere-phase6.sql` | Ramène TEST à l'état vérifié, sans perte de données |
| `…/empreinte.sql` | Empreinte en lecture seule (structure, droits, condensé des données) à comparer avant/après |
| `…/crochet-sms-test.sql` / `…-retrait.sql` | Crochet « Send SMS » : aucun SMS réel, numéros +999000000001 à 009 uniquement |
| `…/attribuer-role-admin.sql` | Rôle d'administration attribué à un compte vérifié (identifiant + e-mail confirmé) |

Régénération : `node scripts/prepare-test-continuation.mjs` ; le test `tests/test-continuation.test.js` échoue si les fichiers versionnés divergent du générateur.

## Garde-fous du paquet

Refus sans aucune modification si : PostgreSQL < 17, marqueur déjà présent, routeur `koki_business` déjà présent, fondation absente, ou **base non vide** (comptes, fiches, contenus, utilisateurs, administrateurs ou photos) — une production est donc toujours refusée. Une seule transaction : toute erreur annule tout.
Le paquet retire aussi le droit d'exécution anonyme de `public.koki_statistics()` constaté sur TEST (la fonction refusait déjà en interne).

## Retour arrière

Exige le marqueur « KOKI TEST » (refusé sur la production ou avant installation). Refuse, sans rien modifier, si des données créées après l'installation seraient perdues : clés d'opération, devis de course, recherches de proximité, dossiers photo anonymes, liste des villages modifiée, ou fiches utilisant un statut introduit par la poursuite (ex. « Archivé »).
Sinon, retire tout ce que la poursuite a ajouté et rétablit les définitions d'origine (extraites de `schema.sql`) : comptes, contenus, fiches compatibles, tarifs, journal, administrateurs et photos sont conservés à l'identique.

Répétition locale (copie de l'état TEST avec les droits par défaut de Supabase) : empreinte après retour arrière **identique** à l'empreinte d'origine ; données d'usage conservées (condensés identiques) ; cycle installation → retour → réinstallation identique ; refus vérifiés.

## Ordre proposé (chaque étape sur autorisation)

1. **C** — vérifier le nom du projet par l'outil Supabase, exécuter `empreinte.sql` (avant), appliquer le paquet, `empreinte.sql` (après), alertes de sécurité.
2. **D** — `crochet-sms-test.sql`, puis Authentication → Hooks → Send SMS → Postgres `koki_test.send_sms` ; numéros de test +999000000001 à 005 avec code fixe ; ne saisir aucun identifiant de fournisseur payant. Compte administrateur créé dans le tableau de bord (« Auto Confirm User »), puis `attribuer-role-admin.sql` avec son UID et son e-mail.
3. **E** — données fictives (variante TEST de `seed.sql` sans le compte administrateur local).
