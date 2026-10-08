# KOKI CONNECT ADMIN

Une solution FAMpro Digital. Application séparée de Koki Connect, responsive pour Mac, iPhone et Android. Aucun fichier de l'application publique n'a été modifié.

## État de livraison

Application compilable, formulaires de contenus et gestion des professionnels/boutiques/produits/services/chauffeurs/véhicules/commandes/demandes/courses ; authentification Supabase et MFA TOTP ; permissions serveur RLS ; journal d'écritures atomique ; statistiques SQL sur la base réelle. En l'absence de serveur configuré, l'application affiche un aperçu sans données et sans accès d'écriture.

**Déployé :** https://koki-connect-admin.vercel.app — backend Supabase Koki Connect (`qsbmzzbiztfqysstepxm`) dans l'organisation FAMpro Évents, région eu-west-2, forfait Free confirmé par le propriétaire. Schéma et durcissement appliqués via MCP, contrôles RLS et flux public vérifiés sur le serveur réel. Invitation envoyée à l'adresse désignée par le propriétaire et rôle superadmin provisionné. Le propriétaire doit définir son mot de passe et enrôler son application TOTP pour utiliser les données. Le parcours authentifié complet et les uploads sont à confirmer avec lui ; aucun code OTP personnel n'est demandé ou conservé par l'agent.

Le portail public consomme maintenant le flux partagé de contenus publiés. Les transactions commerciales et de transport ne sont pas encore raccordées au serveur. Le dépôt GitHub est privé : https://github.com/mourtadafam-star/koki-connect-admin. Vercel ne pouvant pas lire ce nouveau dépôt avec son installation Git actuelle, le déploiement a été effectué avec le bundle statique local vérifié. Les prochains push ne redéploient pas automatiquement Vercel tant que son accès au dépôt n'est pas raccordé. Les variables Vercel ne contiennent que l'URL du projet et sa clé publishable.

## Démarrage

Node 22.12+ (ou Node 24). `npm ci`, puis `npm run dev`. `npm test` exécute les règles métier et le SQL réel sur PostgreSQL embarqué PGlite. `npm run build` construit `dist/`. Les bibliothèques sont verrouillées dans package-lock.json.

Copier `.env.example` en `.env` et renseigner uniquement l'URL du projet et sa clé **publishable** (`sb_publishable_…`). Ne jamais mettre une clé secret/service_role dans une variable VITE : ces variables sont publiques. Aucun secret administrateur n'est nécessaire dans le navigateur.

## Backend dédié

Le projet Supabase « Koki Connect » a été créé dans FAMpro Évents. L'inscription libre et les connexions anonymes sont désactivées. La redirection des invitations pointe vers le site Admin. Utiliser un projet vide : `supabase/schema.sql` est un bootstrap transactionnel, pas une migration à appliquer aveuglément sur une base existante. La version déployée est enregistrée dans les migrations distantes `koki_admin_initial` et `lock_internal_auto_rls_function`. Conserver ce bootstrap pour reproduire le schéma dans une base vide. Configurer les URL Auth et désactiver l'inscription publique dans ce projet tant que le portail public n'a pas de comptes.

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

## Rapport de vérification du 7 octobre 2026

- Tests métier et règles PostgreSQL embarquées : 4 tests réussis, couvrant les contrôles énumérés ci-dessus.
- Serveur réel : flux public HTTP 200 vide ; lecture des comptes/métiers et écriture de contenus sans authentification HTTP 401 / permission denied. Sans MFA, allowed(read)=false.
- Test transactionnel du compte admin avec aal2 : création et modification autorisées, deux événements au journal ; rollback intégral des données de test.
- Supabase Advisors : aucune alerte sur les tables/politiques/fonctions après correction de la fonction automatique rls_auto_enable. Un avertissement Auth demeure : la vérification des mots de passe compromis n'est pas activée (fonction non comprise dans le forfait Free). Ne pas activer de forfait payant sans instruction. La MFA TOTP reste obligatoire pour l'administration.
- npm audit : aucune vulnérabilité connue signalée ; compilation avec le backend configuré réussie (bundle JS environ 62 Ko gzip).
- Page déployée : HTTP 200, CSP/no-referrer/nosniff/frame DENY présents, console sans erreur ; responsive vérifié à 320/390 px. Les écrans de gestion sans connexion ne sont jamais accessibles dans la version connectée.
- Limites de vérification : pas de connexion sous le mot de passe personnel du propriétaire, pas de manipulation de son OTP ; pas d'essai d'upload sous sa session, le flux public a été vérifié sans contenu publié, mais aucune création sous le compte personnel du propriétaire n'a été effectuée.

## Interface et synchronisation éditoriale — 8 octobre 2026

Le tableau de bord reprend le menu vert, la bannière de Koki, les cartes colorées, la répartition des publications, les dernières publications et les événements à venir. Les données de publications sont paginées, sans plafond de 50 pour les compteurs. Recherche des titres disponible dans l’en-tête. Les cartes liées aux données non mesurées affichent « — ».

Le portail utilisateur lit désormais le même flux Supabase de contenus publiés. Actualités, annonces, publicités, événements, sports, opportunités et informations utiles sont synchronisés ; les médias restent privés avec des liens temporaires. Les transactions publiques commerce/transport restent en démonstration locale. La nouvelle interface a été vérifiée sur aperçu local sans données à 320 et 390 pixels ; les parcours personnels MFA et édition restent à vérifier sous le compte du propriétaire.
