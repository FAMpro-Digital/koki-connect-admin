# Module Football — interfaces (phase 4)

Branches : `feature/module-football` (admin, PR #63 ; public, PR #144). **Rien n'est déployé.**

## 1. Site public (koki-connect)

| Fichier | Rôle |
|---|---|
| `assets/portail/foot.js` | Onglet **Football** de la page Sport (six vues : En direct, Aujourd'hui, Résultats, Calendrier, Compétitions, Classements ; filtres Koki / Sénégal / International ; fiche de match) et carte **« Match en direct »** de l'Accueil |
| `assets/portail/foot.css` | Styles, chargés seulement si le module est actif |
| `assets/portail/foot-vue.js` | Présentation sans DOM (scores distincts, périodes, fraîcheur, heure de Koki) |
| `assets/portail/foot-direct.js` | Temps réel : canal Broadcast `koki-foot`, révisions, reconnexion, rechargement après coupure |

### Activation
- Le module est **inactif** tant que `assets/business/config.json` ne contient pas `"football": true` dans
  `modules`. C'est le même principe que `clubs` pour les Académies. Sans ce drapeau, rien ne change
  pour le public : pas d'onglet, pas de carte, pas de feuille de style chargée. Un test navigateur
  le vérifie.
- Modifications des fichiers existants, toutes neutres sans le drapeau :
  - `index.html` : trois balises `<script defer>` et un conteneur `<div id="koki-foot-direct" hidden>`
    placé juste avant le bloc « Koki en direct » ;
  - `assets/portail/sport.js` : l'onglet « Football » est ajouté en tête si `KokiFoot.visible`, et
    sélectionné par défaut tant que l'utilisateur n'a pas choisi un autre onglet.
- `accueil-jour.js` (bloc « Koki en direct ») **n'est pas modifié** : la carte Football est un bloc
  voisin, au même style, au-dessus de lui.

### Données
- Lecture : `public.koki_foot_public` uniquement, avec la clé publishable. Délai maximal de 10 s par
  appel, puis message « Réessayer ».
- Temps réel : client supabase-js déjà présent dans l'application. Si le canal est coupé, un bandeau
  le signale et le module recharge l'état toutes les 30 s.
- Sécurité :
  - le contenu est inséré uniquement en texte (`textContent`), jamais en HTML ;
  - aucun logo externe n'est chargé, car la CSP actuelle les bloquerait : les équipes sont
    représentées par des pastilles à leurs couleurs ;
  - CSP inchangée, et testée en navigateur sans aucune violation.

## 2. Administration (koki-connect-admin)

| Fichier | Rôle |
|---|---|
| `src/foot-admin.js` | Écrans, pensés d'abord pour le téléphone (détail ci-dessous) |
| `src/foot-admin.css` | Styles (CSP `style-src 'self'` respectée : aucun style en ligne) |
| `src/foot-admin-client.js` | Contrôles avant envoi + appels à `koki_foot_admin` (aucun accès direct aux tables) |

Écrans de `foot-admin.js` :
- liste des matchs : en jeu, aujourd'hui, à venir, récents ;
- programmation d'un match ; création de compétitions et d'équipes ;
- saisie rapide : statut, minute, période, événements, correction du score avec motif ;
- annulation d'un événement ; conflits avec l'API ; fournisseurs et seuils.

États gérés :
- chargement, succès, erreur, droits insuffisants ;
- réseau coupé ou serveur indisponible ;
- **conflit de révision** : message et bouton « Recharger » ;
- hors ligne : bandeau.

Doubles soumissions :
- un bouton est désactivé pendant son action (`aria-busy`) ;
- en plus, le contrôle de révision côté serveur refuse un second envoi identique.

Un test navigateur vérifie qu'un double appui sur « + équipe » crée **un seul** événement.

### Branchement proposé (NON appliqué : `app.js` est un module existant)
À valider, puis à appliquer sur la branche :
1. dans `src/app.js` :
   - ajouter `import {monterFootAdmin} from './foot-admin.js';` et `import './foot-admin.css';` ;
   - dans `navigate()`, avant le traitement des clubs :
     `if(k==='football'){if(import.meta.env.VITE_KOKI_FOOT_ADMIN!=='true'){main.append(n('p','Module Football non activé.'));return;}monterFootAdmin(main,{appel:async(command,input)=>{const {data,error}=await db.rpc('koki_foot_admin',{command,input});if(error)throw error;return data;},role:account?.role});return;}`
2. ajouter l'entrée « ⚽ Football » dans `src/navigation-admin.js`, visible seulement si
   `VITE_KOKI_FOOT_ADMIN === 'true'` ;
3. Vercel : `VITE_KOKI_FOOT_ADMIN=true` en *Preview* d'abord, puis en *Production* une fois les
   migrations appliquées en production.

## 3. Banc d'essai navigateur

Dossier `supabase/historique/outils/banc-foot/` (ne touche jamais Supabase).

```bash
sudo -u postgres bash supabase/historique/outils/verifier.sh   # référence de production (une fois)
sudo -u postgres bash supabase/historique/outils/banc-foot/preparer.sh
node supabase/historique/outils/banc-foot/navigateur.mjs       # Chrome + Playwright, captures dans banc-foot/captures/
```

- `serveur-supabase.mjs` : imite les points RPC de Supabase devant la base locale.
  - Le rôle de l'appelant est simulé par l'en-tête `X-Banc-Role`.
  - Une panne se simule avec `POST /__banc/panne` : réponse 503, coupure de connexion, ou lenteur.
- Le site public est servi avec **sa CSP réelle** (celle de `vercel.json`) ; seule l'adresse de
  Supabase y est remplacée par l'adresse locale.
- Le canal Realtime est **simulé** dans le navigateur. Le WebSocket de Supabase n'existe pas sur le
  banc : la connexion réelle reste à tester sur le projet réel.
- Prérequis : Chrome (`CHROME`) et `playwright-core` (`PLAYWRIGHT_CORE`). Ils ne font pas partie des
  dépendances du dépôt.
