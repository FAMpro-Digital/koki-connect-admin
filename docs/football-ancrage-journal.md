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

Outil : `scripts/ancrage-journal.mjs`, avec trois commandes :
- `lire` : produit le reçu signé ;
- `verifier` : contrôle la signature d'un reçu avec la clé publique ;
- `comparer` : compare deux reçus successifs et signale un journal qui a rétréci ou une chaîne réécrite.

Tests : `tests/ancrage-journal.test.js` (5 tests, réussis). La commande SQL `empreinte_journal`
est testée dans `supabase/tests/foot.sql` (section 28) : elle est réservée à la clé serveur.

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

## 5. Exécution (à valider avant toute mise en place)

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
