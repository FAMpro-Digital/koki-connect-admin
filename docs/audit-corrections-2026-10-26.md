# Corrections de l’audit général du 26 octobre 2026

## Réalisé

- Déconnexion permise en présence d’une demande incertaine. La demande est conservée dans un stockage propre au compte pour sa reprise idempotente ; elle ne reste pas exposée dans l’état de l’interface après déconnexion. Une erreur de révocation réseau ne masque plus une fermeture locale confirmée par le SDK.
- Le chauffeur peut devenir indisponible sans GPS ; une position valide reste nécessaire pour devenir disponible. Le caractère limité du suivi en arrière-plan est expliqué.
- Signalement des commentaires ; masquage/rétablissement par l’administration avec permission éditoriale et MFA côté serveur. Motifs conservés dans un journal privé.
- Quota de commentaires indépendant des commentaires supprimés : cinq par minute, trente par jour. Les événements du jour précédent sont purgés au prochain commentaire de ce compte.
- Compteurs J’aime par lot, incluant l’état du compte connecté ; actualisation lors du changement de compte.
- Photos : nouvelle signature lors d’une erreur de chargement, y compris dans l’agrandissement.
- CSP appliquée sans `unsafe-inline` pour les scripts. Styles inline conservés pour compatibilité.
- Flux en réponses de cent éléments, textes complets des actualités/annonces/publicités à la demande. Les autres fiches conservent leur contenu structuré. L’interface charge encore toutes les pages de métadonnées pour préserver recherche et rubriques ; une recherche paginée entièrement côté serveur reste une évolution de capacité.
- Notifications : cinq envois maximum simultanés ; résultats incertains sans renvoi automatique ; traitements dépassant dix minutes classés à vérifier ; écran de suivi sur sept jours. `sent` signifie accepté par le fournisseur, pas reçu sur le téléphone.
- Dix index de clés étrangères et clé primaire du journal des recherches de chauffeurs.
- Statistiques indicatives limitées aux comptes permanents, une action par fiche/type/jour, plafond de deux cents actions distinctes par compte/jour. Les historiques ne sont pas recalculés. Aucun suivi IP ajouté.
- Textes corrigés pour connexion client, mode transport et statistiques. Rubrique de confidentialité avec demandes de copie et suppression à l’assistance existante ; aucun e-mail envoyé automatiquement.

## Installation

Les propositions SQL sont versionnées pour revue, elles ne doivent pas être réexécutées sur un projet déjà migré.

1. `publication-interactions.sql` : prérequis déjà déployé avant cet audit.
2. Migration `general_audit_corrections` : `publication-moderation.sql`, `audit-driver-availability.sql`, `audit-notification-health.sql`, `audit-indexes-tracking.sql`, dans cet ordre.
3. Migration `publication_feed_pages` : `publication-feed-pages.sql`.
4. Migration `notification_policy_initplan` : `audit-notification-policy.sql` (claims évalués une fois par requête).
5. Déployer les deux interfaces après validation CI.

## Points nécessitant encore une configuration ou validation externe

- SMS : fournisseur OTP, identifiants Twilio, expéditeur et validation de livraison/coût. Aucun abonnement acheté, aucun secret inventé. Fonction désactivée.
- Paiement Wave/Orange Money : intégration contractuelle, paiements et webhooks à concevoir et tester. L’application ne prétend pas encaisser les livres payants.
- Protection des mots de passe compromis : option Supabase Auth encore désactivée ; outil de configuration Auth non disponible dans cette session. À activer dans les paramètres Auth si l’offre le permet.
- Notifications sur iPhone/Android réels, suivi avec écran verrouillé : à tester sur appareils consentants. Une application web ne garantit pas le GPS en arrière-plan.
- Restauration de sauvegarde et rotation historique de secrets : à vérifier dans un environnement isolé avec les accès d’exploitation. Aucun essai de restauration sur la production.
- Confidentialité : le parcours de demande existe, mais il ne constitue pas une politique juridique validée ni un traitement automatique des demandes. L’équipe doit définir les durées de conservation et traiter les demandes reçues.

## Vérifications

Tests Node et PostgreSQL embarqué, build administration et contrôles navigateur CI. Les tests utilisent des données fictives et n’envoient aucun SMS ou push réel. Les tables sociales privées ont RLS activé et aucun accès direct anon/authenticated. Les RPC de modération/suivi sont refusés aux visiteurs. Les avertissements « RLS sans policy » sur les tables internes correspondent à leur fermeture volontaire ; ne pas ouvrir ces tables pour faire disparaître ces avertissements.
