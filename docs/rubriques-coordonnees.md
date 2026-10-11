# Rubriques coordonnées (application publique ↔ administration)

Source unique : `src/rubriques-contract.js`, copie identique dans le dépôt public (`assets/portail/rubriques-contract.js`), vérifiée par empreinte SHA-256 dans les deux dépôts.

- **8 rubriques**, dans l'ordre de l'accueil public : Transport, Commerces & Services, Éducation, Emplois & Opportunités, Sports & ASC, Santé, Événements, Services publics (mêmes noms, icônes et couleurs).
- **Menu de l'administration** construit à partir du contrat : chaque rubrique ouvre ses écrans (ex. Transport → Courses, Chauffeurs, Véhicules, Tarifs) ; les rubriques de contenus ouvrent la liste filtrée par type, avec les sous-rubriques « Opportunités jeunes » (Emplois, Stages, Formations, Concours, Bourses, Financements).
- **Publications** : Actualités, Annonces, Publicités, Informations utiles, Numéros utiles, puis « Tous les contenus ».
- **Santé et Services publics** : numéros utiles des groupes concernés et publications de la catégorie Santé. Les lieux de la carte restent pour l'instant fixes dans l'application publique (non modifiables depuis l'administration).
- **Mobile** : barre du bas Accueil · Rubriques · Publier · Contenus ; l'écran « Rubriques » reprend les tuiles colorées de l'accueil public.

Tests : `tests/rubriques.test.js` (admin) et `tests/rubriques-contract.test.cjs` (public) — chaque type de contenu et chaque écran appartient à une seule entrée ; l'accueil public (raccourcis, blocs, filtres, catégories) correspond au contrat.
