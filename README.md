# KOKI CONNECT ADMIN

Une solution FAMpro Digital. Application séparée de Koki Connect, responsive pour Mac, iPhone et Android. Aucun fichier de l'application publique n'a été modifié.

## État de livraison

Application compilable, formulaires de contenus et gestion des professionnels/boutiques/produits/services/chauffeurs/véhicules/commandes/demandes/courses ; authentification Supabase et MFA TOTP ; permissions serveur RLS ; journal d'écritures atomique ; statistiques SQL sur la base réelle. En l'absence de serveur configuré, l'application affiche un aperçu sans données et sans accès d'écriture.

**Pas encore en production :** le projet Supabase Koki Connect n'existe pas, la base n'est pas provisionnée, le premier administrateur n'est pas désigné et l'application publique n'est pas connectée au flux. Aucun compte ni donnée du projet FAMpro Évents n'est modifié. Les connexions réelles, MFA, transferts de photos et synchronisation entre appareils doivent encore être vérifiés sur le projet distant avant déploiement.

## Démarrage

Node 22.12+ (ou Node 24). `npm ci`, puis `npm run dev`. `npm test` exécute les règles métier et le SQL réel sur PostgreSQL embarqué PGlite. `npm run build` construit `dist/`. Les bibliothèques sont verrouillées dans package-lock.json.

Copier `.env.example` en `.env` et renseigner uniquement l'URL du projet et sa clé **publishable** (`sb_publishable_…`). Ne jamais mettre une clé secret/service_role dans une variable VITE : ces variables sont publiques. Aucun secret administrateur n'est nécessaire dans le navigateur.

## Backend dédié

Créer un projet Supabase « Koki Connect » dans l'organisation FAMpro Évents, après vérification du prix affiché dans Supabase. Utiliser un projet vide : `supabase/schema.sql` est un bootstrap transactionnel, pas une migration à appliquer aveuglément sur une base existante. Le préparer en migration CLI avant application en production. Configurer les URL Auth et désactiver l'inscription publique dans ce projet tant que le portail public n'a pas de comptes.

Créer le premier utilisateur via Supabase Auth, puis ajouter son UUID vérifié à koki_admin_members avec role=superadmin, depuis l'interface SQL autorisée. Ne pas déduire le propriétaire d'une adresse e-mail mentionnée dans une autre demande. Les administrateurs suivants sont également provisionnés hors navigateur. Enrôler une application TOTP puis vérifier le code : toutes les opérations protégées exigent aal2 côté base. Les sessions restent uniquement en mémoire ; une recharge demande une nouvelle connexion.

Rôles : superadmin (toutes opérations), editor (lecture et contenus), manager (lecture, commerce/transport), analyst (lecture). Tous les rôles autorisés lisent les données de gestion ; le journal est réservé au superadmin. Aucun rôle client ne peut modifier les membres ou effacer le journal. La désactivation d'un membre retire les droits sans attendre le rafraîchissement du JWT.

## Modèles et limites

Les contenus ont des colonnes structurées avec contraintes, dates, statut, source, image, mise à la une, programmation et campagne. Les métiers sont stockés dans `koki_records` avec un kind, un statut contrôlé et un payload métier ; le schéma applique les contrôles principaux, le client les complète. Les références liées (boutique, chauffeur, client) sont des identifiants saisis : les normaliser avec FK et transactions avant ouverture des commandes ou réservation au public. Cette interface de gestion ne remplace pas une API transactionnelle de stock, paiement et réservation.

Les listes montrent les 50 dernières modifications ; une pagination et une recherche avancée devront être ajoutées pour des volumes supérieurs. Les conflits entre appareils sont détectés via updated_at et les révisions sont fixées par le serveur. Les écritures sont journalisées sans copie du contenu ni données privées clients. Les images (1 Mo, JPEG/PNG/WebP) sont dans un bucket privé et exposées aux visiteurs uniquement quand référencées par un contenu publié. Les URL signées durent 120 secondes. Ne pas utiliser les images de contenus pour des documents personnels. Ajouter une validation serveur des octets/antivirus avant uploads publics.

Les statistiques de publications, commerces et activités métier reflètent la base, jamais une démonstration. Les utilisateurs inscrits proviennent d'Auth. Les utilisateurs actifs, revenus, impressions et clics restent null tant que leurs systèmes de mesure, paiement et événements ne sont pas branchés. Une plateforme publique non synchronisée ne peut pas alimenter ces mesures.

## Synchronisation avec le public

`koki_public_feed()` renvoie uniquement les contenus publiés à la date courante et les campagnes actives/non expirées. `src/public-feed.js` prépare un adaptateur avec la clé publishable et les images privées signées. Le portail existant pourra remplacer la lecture du JSON par cet adaptateur après validation ; son affichage d'images devra accepter les URL Supabase autorisées. Dépublier/supprimer retire le contenu au prochain rafraîchissement. Aucun changement de ce branchement n'est appliqué au site public dans cette livraison.

## Vérification avant déploiement

Tests SQL : anonyme refusé en écriture, brouillons invisibles, MFA obligatoire, rôle non membre refusé, éditeur limité, manager sans écriture éditoriale, pas d'auto-promotion, journal non effaçable, campagnes expirées masquées et droits retirés immédiatement après désactivation. Tests mobile sur navigateur. Ensuite : appliquer la migration sur staging, tester utilisateurs réels et MFA/enrôlement, lancer Supabase Advisors, tester stockage et session après révocation, vérifier les politiques au moyen de comptes distincts, puis déployer. Ne pas déclarer ces vérifications distantes réussies avant provisioning.
