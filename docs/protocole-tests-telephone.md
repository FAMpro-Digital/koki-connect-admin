# Protocole de test sur téléphone — Commerces & Services

Safari sur iPhone et Chrome sur Android. **Données fictives uniquement** (préfixe « TEST », numéros +999). Aucun test sur la production.

## 0. Prérequis (à autoriser avant de commencer)

Un téléphone ne peut pas joindre le Supabase local du Mac : les garde-fous n'acceptent la base locale que sur l'ordinateur lui-même (127.0.0.1), et Safari refuse la géolocalisation hors HTTPS. Les tests sur téléphone se font donc sur la **préproduction TEST** :

1. Projet Supabase TEST (`euvxtwmyoihnutifshay`, gratuit) : appliquer les migrations des branches `dev/commerces-services` — **migration distante sur TEST uniquement, autorisation requise**.
2. Supabase TEST → Authentication : numéros de test (+999…, code fixe), double authentification TOTP activée, inscriptions ouvertes.
3. Aperçus Vercel protégés des deux branches, configurés vers le projet TEST (`scripts/prepare-coordinated-preview.mjs`) — **autorisation requise**. Le site public garde `enabled:false` en production.
4. Comptes fictifs : 1 client, 1 commerçant, 1 prestataire, 1 administrateur (superadmin), 1 gestionnaire, 1 analyste. Application d'authentification (TOTP) sur un téléphone de test.

Noter pour chaque cas : appareil, version iOS/Android, navigateur, résultat (OK / KO), capture si KO.

## 1. Navigation et retour

| # | Action | Attendu |
|---|---|---|
| 1.1 | Accueil → Commerces & Services → une fiche produit → « Voir la boutique » | Chaque écran s'ouvre en haut de page |
| 1.2 | Bouton retour du téléphone (Android) / geste retour (iPhone) | Revient à l'écran précédent, filtres conservés |
| 1.3 | Bouton « ← Retour » de chaque écran | Même comportement |
| 1.4 | « ← Retour à l'accueil » de la rubrique | Retour à l'accueil |
| 1.5 | Rotation de l'écran, police agrandie (Réglages d'accessibilité) | Aucun texte coupé, aucun défilement horizontal |

## 2. Création de compte et fiche professionnelle

| # | Action | Attendu |
|---|---|---|
| 2.1 | Connexion par SMS avec un numéro de test | Code accepté, « Connecté : +999… » |
| 2.2 | Code erroné | Message « Code invalide ou expiré » |
| 2.3 | Espace professionnel → Créer ma fiche, 5 étapes | Numéro prérempli ; « Étape précédente » conserve la saisie |
| 2.4 | Saisir « 77 123 45 67 » | Converti en +221 77 123 45 67 |
| 2.5 | Envoyer | Statut « En attente » expliqué ; boutiques indisponibles |
| 2.6 | Clavier : champs numériques, pas de zoom à la saisie (iPhone) | Clavier adapté, page stable |

## 3. Photos (dont HEIC)

| # | Action | Attendu |
|---|---|---|
| 3.1 | iPhone : photo prise avec l'appareil (format HEIC par défaut) | Aperçu affiché, poids réduit (ex. 3 Mo → < 1 Mo) |
| 3.2 | Photo depuis la galerie (JPEG), puis 5 photos | 5 maximum, la 6ᵉ est refusée |
| 3.3 | Photo très lourde (> 10 Mo) | Message clair, rien n'est envoyé |
| 3.4 | Réseau coupé pendant l'envoi | Message ; « Reprendre la demande interrompue » fonctionne |

## 4. Géolocalisation

| # | Action | Attendu |
|---|---|---|
| 4.1 | « Ajouter ma position actuelle » → Autoriser | Coordonnées affichées |
| 4.2 | Refuser l'autorisation | Message clair ; fiche enregistrable sans position |
| 4.3 | « Retirer la position » puis enregistrer | Position supprimée de la fiche |
| 4.4 | Fiche avec position → « Voir sur la carte » | Ouvre la carte au bon endroit |

## 5. Validation administrative et double authentification (admin)

| # | Action | Attendu |
|---|---|---|
| 5.1 | Connexion admin : e-mail + mot de passe | Code de double authentification demandé |
| 5.2 | Code TOTP erroné, puis correct | Refus, puis accès au tableau de bord |
| 5.3 | Tableau de bord | Indicateurs cohérents avec les fiches TEST |
| 5.4 | Validations commerciales → refuser sans motif | Refus bloqué « Indiquez le motif » |
| 5.5 | Refuser avec motif, puis approuver la fiche corrigée | Le professionnel voit le motif, puis « Actif » |
| 5.6 | Le professionnel renomme sa fiche en ligne | Admin : comparaison, seul le nom surligné ; catalogue : ancien nom tant que non validé |
| 5.7 | Boutique d'une fiche non approuvée | Bouton « Approuver » désactivé avec explication |
| 5.8 | Compte analyste | Indicateurs visibles, validations refusées |
| 5.9 | Admin qui possède une fiche : la valider | Refus « vos propres fiches » |

## 6. Catalogue, recherche et filtres

| # | Action | Attendu |
|---|---|---|
| 6.1 | Onglets Commerces / Boutiques / Produits / Services | Compteurs cohérents |
| 6.2 | Rechercher « riz », « epicerie » (sans accent), un village | Résultats attendus |
| 6.3 | « Disponibles seulement », tri par prix | Épuisés masqués, ordre correct |
| 6.4 | Galerie : faire glisser au doigt | Photos suivantes, compteur 2/3… |
| 6.5 | Réseau 3G lent (mode développeur) | Liste utilisable, photos chargées au défilement |

## 7. WhatsApp et appels

| # | Action | Attendu |
|---|---|---|
| 7.1 | « Appeler » | Composeur ouvert avec le bon numéro |
| 7.2 | « Commander sur WhatsApp » (quantité 2) | WhatsApp s'ouvre, message prérempli : produit × 2, prix FCFA, boutique |
| 7.3 | WhatsApp non installé | Ouverture de la page WhatsApp Web, sans erreur |
| 7.4 | Produit épuisé | Aucun bouton de commande |
| 7.5 | Service sur devis | « Demander un devis sur WhatsApp », message prérempli |
| 7.6 | Panier interne : ajouter, recharger la page | Panier conservé, commande interne possible |

## Résultat attendu avant toute mise en production

Tous les cas OK sur au moins un iPhone récent (Safari) et un Android d'entrée de gamme (Chrome), en Wi-Fi et en 3G.
