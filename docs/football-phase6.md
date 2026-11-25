# Module Football — phase 6 : validation réelle (résultats et procédures)

Exécution de référence : GitHub Actions, PR #63, commit `80bebd5`, 24/11/2026 vers 22 h 50 (Koki).
Rapports JSON expurgés : étape « Redacted reports » du job `foot-essais-reels`.

## 1. Environnement d'essai utilisé : Supabase local éphémère (indépendant)

- Pile Supabase **locale**, dans le Docker du runner GitHub : CLI 2.122.1, PostgreSQL **17.11**, Auth
  (gotrue 2.197.0, MFA TOTP), PostgREST 16.5, Realtime 2.147.1, Storage. Aucun projet distant, aucune
  connexion à la production, aucun secret du dépôt. La pile est détruite en fin de job.
- Structure de production rejouée (`reference/ordre.txt`), puis migrations Football `0500` et `0600`.
- Comptes d'essai créés pour l'exécution (mots de passe et secrets TOTP aléatoires, fichier hors dépôt,
  droits 600) : éditeur MFA, superadmin MFA, éditeur sans MFA, utilisateur sans droits ; match d'essai
  créé par l'éditeur avec ses vraies RPC.
- Durée de vie des jetons : 60 s (pour l'essai « session expirée » avec un vrai jeton).
- Garde-fous : `commun.mjs` refuse l'adresse de production, exige `KOKI_ESSAI_CONFIRME=projet-essai` et une
  adresse `*.supabase.co` ou `127.0.0.1` ; `preparer-supabase-local.sh` refuse un dossier lié à un projet
  distant, une adresse autre que `http://127.0.0.1:54321`, et un fichier de variables situé dans le dépôt.

Limite : ce n'est pas un projet Supabase hébergé (réseau, Kong, limites de débit et réglages Realtime
du service en ligne peuvent différer). Un projet d'essai en ligne reste recommandé avant la production
(procédure §6), sur autorisation écrite.

## 2. Authentification réelle — 8 scénarios exécutés, 8 réussis

| Scénario | Attendu | Obtenu | Statut | Preuve expurgée |
|---|---|---|---|---|
| Éditeur aal2 | lecture et écriture ; tables refusées | conforme | réussi | `aal2`, `amr totp+password` ; écriture révision 2 → 3 puis retour ; `koki_foot.*` : PGRST106 (schéma non exposé) |
| Superadmin aal2 | `verifier_journal` accepté | accepté | réussi | `{"lignes":4,"premiere_alteration":null}` |
| Éditeur, opération superadmin | refusé | refusé | réussi | `regler_verrous` : 42501 |
| Session aal1 | refusé | refusé | réussi | `aal1` ; lecture et écriture : 42501 « double authentification requises » |
| Sans droits | refusé | refusé | réussi | lecture et écriture : 42501 |
| Anonyme | admin et sync refusées ; public lisible | conforme | réussi | 42501 `permission denied for function` ×2 ; `accueil` accepté |
| Session expirée | refus du vrai jeton périmé | refusé | réussi | attente exp + 40 s ; PGRST303 « JWT expired » |
| Interruption d'écriture | jamais d'état intermédiaire | écriture complète | réussi | requête interrompue côté client (AbortError) après validation serveur : révision 4 → 5, écriture entière |

Constats :
- Les refus sont vérifiés comme des refus **de droits** (code 42501), pas comme n'importe quelle erreur.
  Une première exécution avait révélé un défaut du script (commande inexistante, refusée pour une autre
  raison) : corrigé avant l'exécution de référence.
- PostgREST tolère **30 s de décalage d'horloge** : un jeton reste accepté jusqu'à 30 s après `exp`.
- Interruption : le cas observé est « interruption après validation ». Le cas « interruption avant
  validation » (rollback) est couvert par la transaction unique de chaque RPC et par
  `tester-foot-echec-partiel.sh`, pas par cet essai réseau.

## 3. Realtime réel — 8 scénarios exécutés, 8 réussis (deux clients indépendants)

| Scénario | Obtenu | Preuve |
|---|---|---|
| Propagation d'un score | reçu par A et B | 352 ms |
| Ordre des révisions (3 buts rapides) | état final exact, jamais de recul | révisions vues par A : 7, 10 |
| Rejet des anciens messages | ignoré | 0 lecture déclenchée |
| Faux messages (anonyme) | sans effet à l'écran | RPC 42501, table PGRST106, émission Broadcast **acceptée** par le canal public, vraie mise à jour suivante reçue |
| Avalanche (300 signaux en 9 ms) | 1 lecture | plafond théorique 4 |
| Reconnexion | état récupéré | connecte → deconnecte → connecte |
| Réseau instable (3 coupures) | convergence | 855 ms, révision finale = serveur |
| Dépublication | disparu des deux clients | 1 960 ms |

## 4. Canal privé (proposition 0700) — appliqué sur la pile éphémère seulement, 3 essais réussis

| Essai | Résultat |
|---|---|
| Visiteur anonyme abonné au canal privé | reçoit les scores (354 ms) |
| Intrus abonné au canal privé qui émet | message **non relayé** : 0 reçu par l'écouteur (l'envoi est accepté côté client, puis écarté par le serveur faute de politique d'insertion) |
| Transition (double émission) | le canal public reçoit toujours (351 ms) |
| Retour arrière de la proposition | appliqué sans erreur |

## 5. Broadcast : évaluation du risque

- **Aujourd'hui (canal public)** : tout détenteur de la clé publique peut émettre. Effet borné par le
  correctif de phase 5 : aucun contenu affiché, au plus **une lecture `etat_matchs` toutes les 2 s par
  écran ouvert**. Sur N écrans ouverts, une avalanche coûte au plus N/2 lectures par seconde (exemple :
  2 000 écrans → 1 000 lectures/s), chacune limitée à 100 matchs.
- **Limites de la temporisation côté client** : elle protège chaque écran, pas le serveur contre un grand
  nombre d'écrans ; un attaquant qui ouvre lui-même des milliers de connexions agit hors de ce mécanisme
  (limites de débit de la plateforme). Le test d'avalanche ne prouve pas que les 300 messages ont tous
  atteint le client : la plateforme peut en avoir écarté par ses propres limites.
- **Canal privé** : supprime l'émission par les clients (prouvé §4) ; les écouteurs restent anonymes ; le
  serveur seul émet (`realtime.send` dans `koki_foot.diffuser`, SECURITY DEFINER). Politique nécessaire :
  `create policy koki_foot_ecoute on realtime.messages for select to anon, authenticated using
  ((select realtime.topic())='koki-foot' and realtime.messages.extension='broadcast')`, **aucune** politique
  `insert`. Points à vérifier sur le projet hébergé : réglage « Allow public access » de Realtime, et
  fonctionnement avec la clé `sb_publishable_…` du site (l'essai a utilisé la clé anon JWT).
- **Bascule proposée** : 0700 (double émission) → site avec `prive:true` → 0710 (fin du public).

## 6. Procédure : projet Supabase d'essai en ligne (à exécuter seulement après autorisation écrite)

1. Le propriétaire crée, dans l'organisation FAMpro, un projet **distinct** (« koki-essai »), région la plus
   proche de la production, PostgreSQL 17, sans lien avec le projet de production.
2. Il communique l'adresse et la clé publique par un canal hors du chat ; les clés sont placées en
   variables d'environnement (`KOKI_ESSAI_URL`, `KOKI_ESSAI_ANON_KEY`), jamais dans Git.
3. Structure : historique de référence puis `0500`, `0600` (outils de ce dépôt, par connexion directe
   à la base d'essai).
4. Comptes d'essai créés par le propriétaire (éditeur et superadmin avec TOTP, sans MFA, sans droits) ;
   secrets TOTP transmis en variables d'environnement.
5. `node auth-reel.mjs` puis `node realtime-reel.mjs` avec `KOKI_ESSAI_RAPPORT` ; deux téléphones pour le
   protocole manuel (`football-tests-reels.md`).
6. Destruction du projet d'essai, ou mise en pause, après les essais.

## 7. PostgreSQL 17

Job `historique-sql-pg17` (PostgreSQL **17.12**, PGDG) : référence de production 560/0 ; migrations ;
gardes de seconde application ; `foot.sql` **242/242** ; concurrence réelle ; conseils RLS et droits
0/0 ; retour arrière 560/0 ; réapplication ; objets existants **560/560 inchangés** ; échecs partiels
**10/10** sans application partielle. Résultats identiques à la phase 5 (PostgreSQL 16).

Sur la pile Supabase locale (PostgreSQL 17.11) : migrations appliquées, objets existants inchangés
560/560. La comparaison de la structure rejouée avec l'empreinte de production y donne 515 identiques et
45 écarts, tous des clés étrangères vers `auth.users`, des politiques et les droits de
`rls_auto_enable` : objets qui dépendent des tables et fonctions de la plateforme (`auth`, `storage`),
dont la définition locale diffère de la production. Cause probable, non vérifiée ligne par ligne ;
sans lien avec le module Football.
