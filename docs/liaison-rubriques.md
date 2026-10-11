# Liaison des rubriques : Koki Connect Admin → application publique

Tout contenu publié dans l'admin passe par le flux `koki_public_feed` (actualisé toutes les 60 s et au retour dans l'application). Vérifié le 10 octobre 2026 avec un flux simulé contenant chaque type et catégorie de l'admin.

| Saisi dans l'admin | Apparaît dans l'application |
|---|---|
| Contenus › Actualités (toute catégorie) | Rubrique Actualités (filtre par catégorie), « À la une » si cochée, Notifications |
| Contenus › Annonces | Petites annonces, Notifications |
| Contenus › Publicités (active, non expirée) | Bandeaux et cartes sponsorisés de l'accueil |
| Contenus › Sports & ASC (Match à venir, Résultat, Compétition…) | Sports / ASC, Notifications |
| Contenus › Événements (date et lieu) | Événements à venir, Notifications |
| Contenus › Opportunités : Emploi, Stage, Formation, Concours, Bourse, Financement / Appel à projets | Opportunités jeunes (carte de chaque rubrique : nombre d'offres et titres cliquables), liste des opportunités, Notifications |
| Contenus › Informations utiles | Bloc « Informations utiles » de l'accueil |
| 🎓 Établissements scolaires | Écoles (catalogue, recherche, fiche, appel) |
| 📞 Numéros utiles | Numéros utiles et urgences (groupes, recherche, appel) |

Recherche générale : tous les contenus publiés sont indexés.

## Corrections apportées lors de cette vérification

- **Opportunités jeunes** : les six cartes affichaient toujours « Aucune offre publiée » ; elles lisent désormais les opportunités publiées par catégorie.
- **Notifications** : la cloche affiche les publications des 7 derniers jours (hors publicités) au lieu d'un message fixe.
- **Catégories sportives** : « Match à venir », « Résultat », « Compétition » existaient côté public mais pas dans l'admin ; listes désormais identiques (`assets/portail/core.js` = `src/model.js`).
- **Admin, formulaire générique** : « Modifier » sur un numéro utile depuis « Contenus & publicités » ouvre maintenant l'écran Numéros utiles (comme pour les écoles), pour ne pas abîmer sa catégorie ni son format.

## Hors flux éditorial (normal)

- Santé et pharmacies, Services publics, Carte : lieux OpenStreetMap (à compléter sur openstreetmap.org).
- Commerces & Services, Transport : serveur métier (`koki_business`), en attente d'activation.
- Météo : Open-Meteo.
