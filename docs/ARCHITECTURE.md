# Architecture livrée

Koki Connect public (inchangé) → adaptateur public-feed préparé → RPC koki_public_feed → contenus publiés, programmés et médias autorisés.

Koki Connect Admin (application séparée) → Supabase Auth + MFA TOTP → membres administrateurs / RLS PostgreSQL → contenus et registres métier → journal atomique.

Le navigateur ne décide pas des permissions : chaque requête est contrôlée dans la base avec auth.uid, aal2 et le rôle enregistré côté serveur. Aucun user_metadata n’accorde de privilèges. Le bucket média est privé ; seules les images de contenus publiés sont disponibles à la lecture anonyme.

La synchronisation réelle du site public attend son raccordement explicitement validé. Les registres métier administrables sont une première étape ; relations FK, transactions de stock/réservation, événements de publicité et paiements doivent être développés avant leur ouverture transactionnelle au public.
