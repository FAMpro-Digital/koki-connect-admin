# Module Football — essais réels d'authentification et de Realtime

Statut : **protocoles et scripts prêts, NON EXÉCUTÉS.** L'environnement de travail n'a ni projet
Supabase d'essai joignable, ni Supabase local (Docker sans service, réseau sortant bloqué). Les rôles
simulés du banc d'essai ne remplacent pas ces essais : ils restent à faire avant toute mise en service.

## 1. Environnement requis

- Un **projet Supabase d'essai** distinct de la production (`qsbmzzbiztfqysstepxm`), avec la structure
  de production (historique `supabase/historique`) et les migrations Football `0500` et `0600`.
  Les scripts **refusent** l'adresse de production et exigent `KOKI_ESSAI_CONFIRME=projet-essai`.
- Comptes d'essai créés **par le propriétaire** (jamais par l'assistant) :

| Variable (préfixe `KOKI_ESSAI_`) | Compte | Attendu |
|---|---|---|
| `EDITEUR_EMAIL`, `_MOT_DE_PASSE`, `_TOTP` | rôle `editor`, facteur TOTP enrôlé | aal2 : lecture et écriture |
| `SUPERADMIN_…` | rôle `superadmin`, TOTP | aal2 : réglages réservés |
| `SANSMFA_…` | rôle `editor`, sans facteur (ou éditeur connecté sans code) | aal1 : tout refusé |
| `SANSDROIT_…` | utilisateur authentifié sans ligne dans `koki_admin_members` | tout refusé |
| `JETON_EXPIRE` | jeton d'accès d'un compte d'essai, après expiration | refusé |
| `MATCH_ID` | match d'essai publié, « En direct » | remis dans son état initial à la fin |

Le code TOTP est calculé localement (RFC 6238, testé sur les vecteurs officiels) à partir du secret
d'essai ; aucun secret n'est écrit dans un fichier ni affiché.

## 2. Authentification réelle — `supabase/historique/outils/foot-reel/auth-reel.mjs`

| Cas | Vérification |
|---|---|
| Éditeur aal2 | niveau `aal2` ; lecture admin ; saisie d'un score puis retour ; accès direct aux tables `koki_foot.*` refusé |
| Superadmin aal2 | `verifier_journal` accepté |
| Éditeur et réglage superadmin | `regler_verrous` refusé |
| Session sans MFA | niveau `aal1` ; lecture et écriture refusées (« double authentification requise ») |
| Sans droits | lecture et écriture refusées |
| Anonyme | admin et synchronisation refusées ; lecture publique permise |
| Session expirée | jeton périmé refusé |
| Perte de connexion pendant une écriture | requête interrompue : erreur propre ; en base, soit rien, soit l'écriture complète (transaction), jamais un état intermédiaire |

Commande : `node supabase/historique/outils/foot-reel/auth-reel.mjs` (dépend de `@supabase/supabase-js`,
déjà dépendance du projet). Bilan : réussis / échoués / non exécutés (compte absent).

## 3. Realtime réel — `supabase/historique/outils/foot-reel/realtime-reel.mjs`

Deux clients WebSocket indépendants (« appareils » A et B) utilisent le module public
`assets/portail/foot-direct.js` tel quel :

1. **Changement de score** saisi par l'éditeur : reçu par A et B, révision strictement croissante.
2. **Message ancien** rejoué : ignoré.
3. **Client non autorisé** : écriture par RPC refusée, écriture directe en table refusée ; faux message
   Broadcast `score 9–9, révision 999999` : **aucun effet sur l'affichage**.
4. **Reconnexion** : B coupé, un score change, B se reconnecte et récupère l'état serveur.
5. **Dépublication** : le match disparaît de A et B, puis il est republié.

### Protocole manuel complémentaire (deux téléphones réels)

1. Téléphone 1 : site public, carte « Match en direct ». Téléphone 2 : site public, onglet Sport › Football.
2. Poste admin (éditeur aal2) : but à domicile. Attendu : les deux écrans changent en moins de 3 s.
3. Téléphone 2 en mode avion 1 minute ; deux buts saisis ; retour réseau. Attendu : bandeau « hors
   ligne », puis score exact sans recharger la page.
4. Dépublier le match : il disparaît des deux écrans.
5. Noter pour chaque étape : heure, délai observé, capture d'écran.

## 4. Risque identifié et corrigé : canal Broadcast public

Le canal `koki-foot` est **public** (`private=false`) : quiconque détient la clé publique peut y émettre.
Avant cette phase, le site appliquait le contenu du message : un tiers pouvait afficher un faux score
et, avec une révision énorme, bloquer les vraies mises à jour jusqu'au rechargement de la page.

Correction (dépôt public, `foot-direct.js`) : un message n'est plus qu'un **signal**. Son contenu n'est
jamais affiché ; l'état est relu sur le serveur (`etat_matchs`), avec un regroupement de 300 ms et au
plus une lecture toutes les 2 s. Tests : 5 tests unitaires (faux score, fausse révision, fausse
dépublication, avalanche de 1 500 messages) et 1 scénario navigateur.

Amélioration recommandée, **non appliquée** (modification des réglages Realtime de production, à
autoriser par écrit) : canal **privé** avec une politique RLS sur `realtime.messages` autorisant la
lecture à `anon`/`authenticated` et réservant l'émission à la base (`realtime.send` depuis les RPC).
Coût restant sans cela : un tiers peut provoquer des relectures limitées (1 toutes les 2 s par écran).
