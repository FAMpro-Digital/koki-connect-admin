# Notifications personnelles, Web Push et SMS

Implémentation préparée le 25 octobre 2026. Aucun envoi publicitaire. Les envois extérieurs sont désactivés par défaut.

## Comportement

Les changements de statut de commandes, demandes de services et courses créent des notifications pour le client et le professionnel/chauffeur concernés. Les créations et validations de dossiers professionnels préviennent le propriétaire ; les dossiers à valider préviennent les superadministrateurs et managers actifs. Aucune reprise des événements historiques. Une contrainte destinataire + dossier + révision évite les doublons. Les écritures de notifications ne sont pas autorisées aux clients.

L'application publique conserve les publications récentes et ajoute les notifications personnelles à la cloche. L'administration dispose d'un écran Notifications. Lecture des 50 dernières, marquage comme lue, actualisation toutes les 30 secondes lorsque l'écran est visible. Nettoyage de l'écran au changement de compte ; aucune mise en cache des données personnelles.

Les alertes push affichent un texte générique et ouvrent les notifications, jamais une URL fournie par le message. Chrome/Android, Firefox et Safari/iOS sont pris en charge par la liste de services autorisés. Sur iPhone, ajouter l'app à l'écran d'accueil. Les autres fournisseurs push sont refusés plutôt que d'autoriser une requête vers une destination arbitraire. Maximum cinq appareils par compte. Déconnexion volontaire : désabonnement du navigateur, même en cas d'erreur serveur.

SMS transactionnels : consentement explicite, numéro +221 confirmé par Supabase Auth, cinq tentatives maximum par jour et par compte, désactivation immédiate avant l'envoi suivant. Le formulaire utilise updateUser(phone) puis verifyOtp(type=phone_change), sans changer le parcours de connexion e-mail. Twilio est un adaptateur proposé : aucun compte payant n'est créé.

## Installation et activation

1. Appliquer `supabase/proposals/notifications.sql` après les migrations métier existantes. Tester préalablement sur une base TEST. La proposition a été exécutée avec PostgreSQL embarqué (PGlite) et les fixtures métier.
2. Déployer la branche administration et la branche publique associée. Les notifications internes fonctionnent sans fournisseur externe.
3. Générer une paire VAPID avec `node -e "console.log(require('web-push').generateVAPIDKeys())"` dans un terminal sécurisé. Ne jamais versionner la clé privée.
4. Sur Vercel ADMIN uniquement, définir `VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_SUBJECT` (mailto réel), `NOTIFICATION_DISPATCH_SECRET` (aléatoire, au moins 32 octets), `SUPABASE_URL` et une clé serveur valide `SUPABASE_SERVICE_ROLE_KEY`. Ne pas réutiliser une clé compromise. Mettre `NOTIFICATION_PUSH_ENABLED=true`.
5. Mettre la clé **publique** dans `assets/business/notifications.json` et dans `VITE_VAPID_PUBLIC_KEY` de l'administration. Redéployer. La clé privée ne doit jamais avoir le préfixe VITE_.
6. Planifier un appel HTTPS au serveur admin `/api/notifications-dispatch` toutes les minutes, avec l'en-tête `Authorization: Bearer <NOTIFICATION_DISPATCH_SECRET>`. L'endpoint accepte GET/POST, ignore toute cible fournie par le client et réserve au plus 20 livraisons par passage. Choisir le planificateur selon l'offre disponible ; aucun abonnement ni cron payant n'est activé automatiquement. Les notifications internes ne dépendent pas du planificateur.
7. Pour les SMS, configurer d'abord un fournisseur OTP dans Supabase Auth et tester un numéro consenti. Pour l'adaptateur transactionnel Twilio : `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_MESSAGING_SERVICE_SID`, puis `NOTIFICATION_SMS_ENABLED=true` sur le serveur. Valider expéditeur, coût et livraison au Sénégal. Ensuite seulement activer `smsEnabled` dans la configuration publique et `VITE_NOTIFICATION_SMS_ENABLED=true` dans l'admin.
8. Faire un test réel avec un compte de test consenti sur iPhone et Android : inscription push, nouvel événement, ouverture, désactivation et déconnexion. Tester un SMS à son propre numéro avant toute ouverture générale.

## Exploitation et limites

La file et le journal ne sont accessibles qu'au serveur. L'état `sent` signifie **accepté par le fournisseur**, pas une preuve de réception sur le téléphone. Une livraison `processing` ou `failed` n'est jamais renvoyée automatiquement : après une interruption réseau, le fournisseur peut avoir reçu la demande. Vérifier son journal avant une reprise manuelle. Une automatisation de reprise avec accusés de réception est une évolution distincte.

Les abonnements expirés (404/410) sont supprimés. Les destinataires, consentements et téléphones confirmés sont revérifiés au moment de l'envoi. Une notification n'est envoyée qu'aux abonnements créés avant elle, et seulement pendant les dernières 24 heures. Une révocation de consentement empêche les nouveaux envois ; elle ne peut pas annuler un message déjà accepté par le fournisseur. Prévoir une purge périodique des notifications/livraisons anciennes selon la politique de conservation choisie.

Retour arrière sans supprimer les données : désactiver les deux flags serveur, arrêter le planificateur, retirer le trigger `koki_notify_record`, puis revenir aux versions précédentes des interfaces. Conserver les tables tant que les données sont nécessaires.

## Vérification locale

- `node --test tests/notifications*.test.js` : isolation, anti-usurpation, événements métier, file, plafonds, contrôle des destinations push, consentement SMS, échec fournisseur sans doublon.
- `npm test` et `npm run build` : régression administration.
- Dépôt public : `npm test`, `npm run lint`, `npm run test:e2e -- notifications.spec.mjs`.

Les tests d'envoi utilisent des fournisseurs simulés : aucun SMS réel ni push utilisateur n'est envoyé par les tests.
