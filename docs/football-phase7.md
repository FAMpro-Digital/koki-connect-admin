# Module Football — phase 7 : sécurisation GitHub et validation sur Supabase hébergé

**Statut : phase 7 NON validée.** Aucun projet Supabase d'essai hébergé n'a été créé (autorisation écrite
non donnée) : **aucun essai hébergé n'a été exécuté**. Tout ce qui suit marqué « local » a tourné sur une
pile Supabase locale éphémère (CI `foot-essais-reels`), qui n'est **pas** un projet hébergé.

## 1. GitHub
Voir `docs/protection-branches/README.md` : état des rulesets, rulesets proposés (fichiers JSON prêts),
revue des workflows Actions, recommandations de sécurité du dépôt.

## 2. Projet Supabase d'essai hébergé — procédure (à exécuter après autorisation écrite)

| Exigence | Mise en œuvre |
|---|---|
| Indépendant de la production | projet distinct créé par le propriétaire (nom « koki-essai »), sans lien ni clé partagée avec `qsbmzzbiztfqysstepxm` ; les scripts refusent la référence de production partout (adresse, base, clés) |
| PostgreSQL 17 | version par défaut des nouveaux projets ; vérifiée par le script (`server_version`) |
| Aucune donnée réelle | structure seule (historique de référence) ; le script refuse un projet non vide sans marqueur ; tâches cron désactivées |
| Identifié comme essai | schéma `koki_essai` + ligne « ENVIRONNEMENT D'ESSAI — aucune donnée réelle » ; exigé par tous les scripts suivants |
| Comptes aléatoires | 4 comptes `…@essai.koki.invalid`, mots de passe et secrets TOTP aléatoires par exécution, fichier hors dépôt (600) |
| MFA TOTP | à activer par le propriétaire dans Authentication › MFA (TOTP) ; enrôlé par le script pour l'éditeur et le superadmin |
| Realtime et RPC | Realtime activé ; réglage « Allow public access » à relever avant les essais et à noter dans le rapport |
| Clés | `sb_publishable_…` et `sb_secret_…` du projet d'essai, en variables d'environnement seulement ; une clé secrète passée comme clé publique est refusée |

Étapes :
1. Le propriétaire crée le projet, active la MFA TOTP, relève le réglage Realtime « Allow public access ».
2. Il crée l'environnement GitHub `koki-foot-essai` (relecteur obligatoire) avec les secrets
   `KOKI_ESSAI_URL`, `KOKI_ESSAI_DB_URL`, `KOKI_ESSAI_PUBLISHABLE_KEY`, `KOKI_ESSAI_SECRET_KEY` — ou les
   exporte dans un terminal de confiance (jamais dans Git, jamais dans le chat).
3. Lancement :
   - **depuis un poste de confiance** (possible dès maintenant) :
     `KOKI_ESSAI_AUTORISATION=OUI-ESSAI-<ref> KOKI_ESSAI_ENV=~/koki-essai.env bash supabase/historique/outils/foot-reel/preparer-projet-essai.sh`,
     puis `auth-reel.mjs`, `realtime-reel.mjs`, `bascule-canal.mjs` (avec `KOKI_ESSAI_DB_URL`) ;
   - **ou par le workflow manuel** `foot-essais-heberges.yml` : GitHub ne permet son lancement qu'une fois
     le fichier présent sur `main`.
4. Rapports JSON expurgés (attendu, obtenu, statut, preuve) ; mise en pause ou suppression du projet ensuite.

## 3. Ce qui a été exécuté en phase 7 (LOCAL uniquement, CI commit `65038de`)

Clé publique utilisée : **`sb_publishable_…`** (locale) — première vérification que les scripts et le
canal privé fonctionnent avec ce type de clé, à confirmer sur le projet hébergé.

| Suite | Local | Hébergé |
|---|---|---|
| Authentification (8 scénarios) | 8/8 réussis | non exécuté |
| Realtime public, deux clients (8) | 8/8 réussis | non exécuté |
| Canal privé (3) | 3/3 réussis | non exécuté |
| Bascule complète (5 étapes) | 5/5 réussis | non exécuté |
| Ancrage de bout en bout | réussi (2 attaques détectées) | — |

Bascule (local) :
1. 0700 : révision 19 reçue sur le canal public ET le canal privé.
2. Intrus abonné au canal privé : envoi accepté côté client, **non relayé** (0 reçu).
3. Écran `prive:true` à jour en 353 ms.
4. 0710 : **0 message public** reçu ; le privé continue (révision 21).
5. Retour arrière : politique supprimée ; nouvel abonnement privé refusé (`CHANNEL_ERROR`) ; public
   rétabli (révision 22).

Ancrage (local, vraie RPC `empreinte_journal` avec la clé serveur locale) :
- 2 reçus signés, série valide, aucun secret dans les reçus ;
- **réécriture d'une ligne puis recalcul complet de la chaîne** par un superutilisateur : `verifier_journal()`
  en base ne signale rien (contrôle interne trompé) ; l'ancrage refuse : « Chaîne RÉÉCRITE » ;
- **troncature** (dernière ligne supprimée) : `verifier_journal()` ne signale rien ; l'ancrage refuse :
  « Journal TRONQUÉ ».

## 4. Ancrage — automatisation préparée (non créée)
`supabase/historique/outils/ancrage-depot/` : modèle de tâche quotidienne pour un dépôt privé
indépendant, trousseau, générateur de clé hors ligne, procédure de rotation, seconde copie à brancher.
