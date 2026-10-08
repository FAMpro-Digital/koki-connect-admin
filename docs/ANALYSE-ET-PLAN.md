# Koki Connect Admin — analyse et première étape

Date : 8 octobre 2026. Une solution FAMpro Digital.

## Architecture existante

Le projet existant est conservé : interface JavaScript avec Vite, client Supabase, authentification et base partagées avec le portail public. Les deux applications restent distinctes. Le portail public consomme le flux `koki_public_feed` ; les brouillons, contenus futurs et campagnes expirées ne sont pas exposés par ce flux.

L'administration dispose déjà de formulaires de contenus, programmation par date, mise à la une, source, image unique, publication/dépublication et suppression. Des formulaires génériques gèrent professionnels, boutiques, produits, services, chauffeurs, véhicules, commandes, demandes de services et courses. Ces formulaires ne constituent pas encore tous les processus métier demandés.

La base contient les tables `koki_contents`, `koki_records`, `koki_users`, `koki_admin_members` et `koki_audit`, avec contrôle des accès côté serveur. Les opérations administratives exigent un membre autorisé et une session MFA de niveau AAL2. Les secrets de service ne sont pas fournis au navigateur.

La vérification en lecture a trouvé un compte, aucun contenu et aucun registre commercial. Les interactions Transport et commerce en démonstration dans l'application publique ne sont pas des transactions serveur et ne doivent pas alimenter artificiellement les statistiques.

## Tableau de bord développé localement

- Quatorze indicateurs, distinguant une valeur mesurée à zéro d'une mesure indisponible.
- Chauffeurs disponibles comptés par statut ; professionnels et chauffeurs à vérifier comptés séparément.
- Actions rapides pour créer une actualité, une annonce, une publicité, un professionnel ou un chauffeur, selon les permissions existantes.
- Graphiques existants de publications sur six mois et répartition des contenus conservés. Ils représentent les contenus actuellement publiés, pas un historique de visiteurs.
- Export CSV des indicateurs, avec protection contre l'interprétation des cellules comme formules.
- Vue imprimable pour enregistrer un PDF depuis le navigateur.
- Navigation inférieure sur mobile et menu latéral sur ordinateur.
- Accès au journal masqué aux rôles sans permission correspondante ; les contrôles serveur restent obligatoires.

Fichiers modifiés : `src/app.js`, `src/dashboard.js`, `src/styles.css`, `tests/dashboard.test.js`. Aucun changement de la base distante ou de l'application publique pour cette étape.

Les utilisateurs actifs, revenus, impressions, clics et annonces en attente ne disposent pas encore des sources de mesure nécessaires. L'interface l'indique explicitement. L'aperçu visuel local sans serveur n'affiche aucune donnée réelle et désactive les opérations d'écriture.

## Développement progressif restant

1. **Contenus et annonces** : extraire les formulaires de `src/app.js` dans des modules dédiés ; ajouter images multiples, archivage, propositions et validation/refus. Créer une migration de statuts et de références médias ; adapter le flux public et ses règles de stockage avant activation. Conserver les contenus existants.
2. **Publicités** : ajouter annonceur, budget, facturation, programmation et suspension. Introduire les événements d'affichage réellement visibles et les clics, avec déduplication et contrôle serveur. Ne pas incrémenter un compteur à chaque simple lecture du flux.
3. **Transport et commerce** : réutiliser les registres existants, ajouter vérifications, transitions autorisées, tarification, réclamations et demandes persistées côté serveur. Connecter ensuite l'application publique, sa géolocalisation et ses parcours de commande au backend.
4. **Autres rubriques** : vues spécialisées pour établissements, santé, services publics, coordonnées, événements, sports, opportunités et signalements ; recherche et filtres adaptés aux données.
5. **Permissions et sécurité** : migration contrôlée des quatre rôles actuels vers les six rôles demandés, matrice de permissions par module, tests SQL de chaque opération et catégorie. Les contrôles d'interface seuls ne sont jamais une autorisation.
6. **Compte et MFA** : compléter les parcours de récupération, vérifier les sessions navigateur et application installée. Prévoir remplacement puis révocation du facteur compromis, avec vérification de l'identité et du nouveau facteur. Ne pas supprimer un facteur pour contourner la connexion ; ne jamais journaliser une clé ou un code. La saisie de nouveaux identifiants reste une action personnelle de l'utilisateur.
7. **Mesures et déploiement** : connecter les sources réelles d'activité et de revenus ; tester les exports, synchronisations, notifications et publication sur un environnement de validation avant autorisation de production.

Les migrations à créer seront placées dans le dossier Supabase existant ; les tests de permissions compléteront les tests SQL actuels. Les modules d'interface pourront être séparés dans `src/modules/`, en conservant un client d'authentification unique et les composants existants.

## Vérifications de cette étape

- Sept tests automatisés réussis : calculs, CSV, validations métier et exécution SQL des règles RLS/MFA/rôles, programmation et audit.
- Compilation de production réussie ; syntaxe JavaScript et différences de fichiers vérifiées.
- Aperçu local testé à 320 et 390 pixels : aucun débordement horizontal à 320 pixels et aucune erreur JavaScript observée.
- Les protections SQL sont testées dans une base locale ; la connexion personnelle MFA, l'export authentifié et le rendu sur un iPhone ou Android physique nécessitent encore une validation réelle. L'émulation de dimensions ne remplace pas ces essais.

La production reste inchangée. Cette première étape doit être validée avant tout déploiement.
