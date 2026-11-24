# Module Football — proposition d'ancrage externe du journal des corrections

Statut : **proposition, outil écrit et testé localement. AUCUNE automatisation déployée ni programmée.**

## 1. Problème

Le journal `koki_foot.corrections` est chaîné : chaque ligne porte une empreinte SHA-256 qui inclut
celle de la ligne précédente. Dans la base, une altération est donc détectable par
`verifier_journal()`.

Mais quelqu'un qui contrôle la base (propriétaire ou superutilisateur) peut réécrire des lignes puis
**recalculer toute la chaîne** : la vérification redevient valide. Pour s'en prémunir, il faut une
trace hors de Supabase que ce compte ne peut pas modifier.

## 2. Solution proposée

Chaque jour (proposition : 23 h 55 à Koki), une tâche fait trois choses :
1. **Lecture** : elle appelle `koki_foot_sync('empreinte_journal')` avec la clé serveur, et obtient
   le dernier identifiant, la dernière empreinte, le nombre de lignes et le résultat de la
   vérification complète.
2. **Refus si altéré** : si la vérification signale une altération, aucun reçu n'est produit, et
   une alerte est envoyée au responsable.
3. **Signature** : la tâche signe le reçu avec une **clé Ed25519 qui n'est pas chez Supabase**, puis
   l'archive à deux endroits que le compte Supabase ne peut pas modifier.

Outil : `scripts/ancrage-journal.mjs`, avec quatre commandes :
- `lire [reçu précédent]` : produit le reçu signé (version 2) ;
- `verifier` : contrôle la signature d'un reçu avec la clé publique ;
- `comparer` : compare deux reçus successifs et signale un journal qui a rétréci ou une chaîne réécrite ;
- `suite <trousseau> <reçus…>` : vérifie une série complète (voir 2 bis).

Tests : `tests/ancrage-journal.test.js` (12 tests, réussis). La commande SQL `empreinte_journal`
est testée dans `supabase/tests/foot.sql` (section 28, 5 tests) : elle est réservée à la clé serveur.

## 2 bis. Contenu d'un reçu et contrôles (version 2)

| Champ | Rôle |
|---|---|
| `dernier_id`, `empreinte`, `lignes`, `lu_le` | état du journal au moment de l'ancrage |
| `controle` | `{id, empreinte}` : empreinte **actuelle**, relue en base, de la dernière ligne du reçu précédent |
| `precedent` | SHA-256 du reçu précédent (chaîne des reçus) |
| `cle` | identifiant de la clé (16 premiers caractères du SHA-256 de la clé publique), couvert par la signature |
| `signature` | Ed25519 sur tous les champs ci-dessus, en JSON canonique |

Contrôles réalisés (et testés) :
- **Signature et vérification** : toute modification d'un champ invalide la signature ; une autre clé
  ne la valide pas.
- **Continuité de la chaîne** : la ligne `controle.id` doit avoir gardé l'empreinte ancrée la veille.
  Comme chaque empreinte inclut la précédente, cela prouve que **toutes** les lignes déjà ancrées sont
  intactes, même si quelqu'un a recalculé la chaîne en base. Sinon : « Chaîne RÉÉCRITE », pas de reçu.
- **Journal tronqué** : ligne de contrôle disparue (`empreinte` nulle), moins de lignes ou identifiant
  plus petit qu'au reçu précédent : « Journal TRONQUÉ », pas de reçu, alerte.
- **Série de reçus** : reçu manquant, remplacé ou réordonné détecté par `precedent` et par les dates.
- **Absence de secrets** : un reçu ne peut contenir que les champs listés ; tout ce qui ressemble à une
  clé privée, un jeton JWT ou une clé serveur est refusé (`sansSecret`).

## 2 ter. Rotation des clés

Le trousseau public (`trousseau.json`, versionné dans le dépôt d'ancrage) :

```json
{"cles":[
 {"id":"<empreinte clé 1>","publique":"-----BEGIN PUBLIC KEY-----…","valide_du":"2026-12-01T00:00:00Z","valide_au":"2027-06-01T00:00:00Z"},
 {"id":"<empreinte clé 2>","publique":"-----BEGIN PUBLIC KEY-----…","valide_du":"2027-06-01T00:00:00Z","valide_au":null}
]}
```

Procédure : générer la nouvelle clé hors ligne, l'ajouter au trousseau avec sa date de mise en service,
fixer `valide_au` de l'ancienne, remplacer le secret `KOKI_ANCRAGE_CLE`, puis détruire l'ancienne clé
privée. L'ancienne clé publique reste dans le trousseau pour vérifier l'historique. Un reçu signé avec
une clé retirée après sa date de retrait, une clé absente du trousseau ou un trousseau dont
l'empreinte ne correspond pas à la clé sont refusés. Rotation conseillée : tous les 6 mois, et
immédiatement en cas de doute sur la clé.

## 3. Où stocker les reçus (à choisir)

| Option | Avantages | Limites |
|---|---|---|
| **A. Dépôt GitHub privé dédié** (`koki-ancrage`), un fichier par jour, branche protégée et historique non réécrivable | Gratuit, horodaté par GitHub, historique visible | Nécessite un jeton GitHub limité à ce seul dépôt |
| **B. Courriel quotidien** à une adresse hors organisation (direction FAMpro) | Simple, copie hors de toute infrastructure technique | Archive moins structurée |
| **C. Stockage objet en écriture unique** (par exemple un bucket avec verrouillage d'objet) | Inaltérable par conception | Coût et configuration supplémentaires |

**Recommandation : A + B.** Le dépôt sert de référence vérifiable ; le courriel sert de copie
indépendante.

## 4. Clés

- **Clé privée Ed25519** : générée hors de Supabase. Elle n'est enregistrée que dans la variable
  `KOKI_ANCRAGE_CLE` de la tâche planifiée, jamais dans un dépôt.
- **Clé publique** : versionnée dans le dépôt d'ancrage, pour que n'importe qui puisse vérifier.
- **Clé serveur Supabase** (`KOKI_SERVICE_KEY`) : variable d'environnement de la tâche seulement.
  La tâche ne fait que lire l'empreinte.

## 5. Automatisation proposée (NON programmée, NON déployée)

Dépôt privé `FAMpro-Digital/koki-ancrage` (à créer par le propriétaire), protection de `main` contre
la réécriture d'historique, contenant `trousseau.json`, `recus/AAAA/MM/JJ.json` et ce workflow :

```yaml
name: Ancrage quotidien du journal Football
on:
  schedule: [{cron: '55 23 * * *'}]   # 23 h 55 à Koki (UTC+0)
  workflow_dispatch: {}
permissions: {contents: write}
jobs:
  ancrer:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with: {repository: FAMpro-Digital/koki-connect-admin, path: outil, sparse-checkout: scripts/ancrage-journal.mjs}
      - name: Lire, contrôler, signer
        env:
          KOKI_SUPABASE_URL: ${{ secrets.KOKI_SUPABASE_URL }}
          KOKI_SERVICE_KEY: ${{ secrets.KOKI_SERVICE_KEY }}
          CLE: ${{ secrets.KOKI_ANCRAGE_CLE_PEM }}
        run: |
          umask 077; printf '%s' "$CLE" > "$RUNNER_TEMP/cle.pem"
          prec=$(ls recus/*/*/*.json 2>/dev/null | sort | tail -1)
          jour=recus/$(date -u +%Y/%m/%d).json; mkdir -p "$(dirname "$jour")"
          KOKI_ANCRAGE_CLE="$RUNNER_TEMP/cle.pem" node outil/scripts/ancrage-journal.mjs lire $prec > "$jour"
          node outil/scripts/ancrage-journal.mjs suite trousseau.json $(ls recus/*/*/*.json | sort | tail -30)
      - name: Archiver
        run: git add recus && git -c user.name=ancrage -c user.email=ancrage@koki.invalid commit -m "Ancrage $(date -u +%F)" && git push
      - name: Seconde copie indépendante (courriel à la direction FAMpro)
        if: always()
        run: echo "Envoi du reçu du jour (ou de l'alerte) par un service de courriel choisi par le propriétaire"
```

- **Échec ou alerte** (journal altéré, tronqué, réécrit, lecture impossible) : le job échoue, GitHub
  envoie une notification ; aucun reçu n'est écrit.
- **Seconde copie** : courriel quotidien du reçu à une adresse hors organisation technique (direction
  FAMpro). Le service d'envoi reste à choisir par le propriétaire (aucun abonnement pris).
- Secrets à créer par le propriétaire dans le dépôt d'ancrage : `KOKI_SUPABASE_URL`, `KOKI_SERVICE_KEY`,
  `KOKI_ANCRAGE_CLE_PEM`. Rien n'est stocké dans les dépôts de code.

## 5 bis. Exécution (à valider avant toute mise en place)

- Support possible :
  - une tâche planifiée GitHub Actions dans le dépôt d'ancrage (le plus simple) ;
  - une tâche Vercel, en tenant compte des limites du forfait.
- Les jours où la lecture échoue, l'échec doit être journalisé et une alerte envoyée.
- Contrôle mensuel : `comparer` entre le premier et le dernier reçu du mois, et `verifier_journal`
  en base.

## 6. Ce que cela ne couvre pas

- Une modification faite le jour même, avant l'ancrage du soir : elle est détectée le lendemain
  seulement si elle touche des lignes déjà ancrées.
- La suppression de tout le schéma : le dernier reçu prouve alors l'état antérieur, sans permettre
  de restaurer les données. Les sauvegardes Supabase restent nécessaires.
