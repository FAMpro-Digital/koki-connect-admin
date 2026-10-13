# Numéros utiles — écran d'administration

Menu « 📞 Numéros utiles ». Les numéros sont des contenus `koki_contents` : `type = 'Informations utiles'`, `categorie = 'Numéros utiles'`, `texte` au format `src/numeros-contract.js` (**à garder identique** à `assets/portail/numeros-contract.js` de Koki Connect, comme `education-contract.js`).

- Ajout / modification : nom, groupe, téléphone (international ou numéro court), description, **source obligatoire**, date de vérification, visibilité et date de publication.
- Alerte en cas de numéro déjà enregistré ; archivage et réactivation (le flux public n'affiche plus un numéro archivé).
- « Importer les numéros d'urgence nationaux » : 17, 18, 1515, 800 00 20 20 en **brouillon**, source citée, à relire puis publier.
- Permission `content` (editor, superadmin), MFA aal2 ; aucune migration nécessaire.

L'application publique affiche les numéros publiés, complétés par les numéros d'urgence intégrés (secours si le serveur ne répond pas).

Vérifications : `tests/numeros.test.js` ; insertion par un éditeur, lecture par `koki_public_feed()` et archivage contrôlés sur le schéma `supabase/schema.sql` (PostgreSQL 16) ; parcours de l'écran testé dans Chromium avec un serveur simulé.
