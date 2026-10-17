# Invitations administrateurs et validation des produits — 17 octobre 2026

Cette proposition couvre les nouveaux besoins du client et de l'administration. Aucun script ni paramètre n'a été appliqué en production. Aucun e-mail réel n'a été envoyé.

## Comportement

Paramètres affiche « Inviter un administrateur » au superadministrateur. Une adresse e-mail et un rôle (gestionnaire, éditeur, lecteur) suffisent. L'API serveur vérifie la session avec Supabase Auth, le rôle actif et le niveau MFA aal2. Les autres rôles, les sessions sans MFA et les origines différentes sont refusés. Aucune clé privilégiée n'entre dans le code navigateur. Le nouvel administrateur définit son mot de passe, puis configure sa MFA avant d'accéder aux écrans autorisés. L'invitation ne peut pas créer un autre superadministrateur.

Les liens portent une destination explicite : `?action=invite` ou `?action=recovery`. Les erreurs Auth sont reconnues dans le fragment et dans la query. La destination est nettoyée après définition du mot de passe.

Chaque nouveau produit est enregistré masqué, verrouillé contre sa remise en ligne par le commerçant et identifié comme « En attente de validation ». Il apparaît dans Validations → Nouveaux produits. Une approbation conserve les contrôles existants (MFA, droits commerce, propriétaire différent, parent actif et révision exacte). Les produits déjà publiés restent inchangés. Les suspensions et archives existantes restent disponibles. Le client affiche la décision et son motif lorsqu'il existe.

## Activation coordonnée, après validation

1. Tester sur un projet isolé utilisant les propositions existantes, puis `supabase/proposals/produits-validation.sql` **une seule fois**. La migration est transactionnelle et échoue sans modification si déjà installée. Ne pas rejouer `commerce-modernisation.sql` ensuite : son routeur précédent a été conservé sous `commerce_admin_before_product_review`.
2. Configurer côté serveur Vercel Admin uniquement : `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `KOKI_ADMIN_ORIGIN` (origine HTTPS exacte du site Admin). Jamais de préfixe `VITE_` pour la clé privilégiée. Les valeurs sont saisies via les paramètres sécurisés, pas dans Git.
3. Autoriser dans Supabase Auth les URL exactes Admin `/?action=invite` et `/?action=recovery`. Le template d'invitation doit utiliser `{{ .ConfirmationURL }}` ; ne pas remplacer par le seul SiteURL. Un environnement Preview exige son origine et ses redirections propres, cohérentes avec `VITE_ADMIN_PREVIEW_URL`.
4. Déployer ensemble Admin et client après validation de la migration. Les déploiements automatiques des deux branches de travail sont désactivés.
5. Avec une adresse de test autorisée, vérifier réception réelle, lien à usage unique, définition du mot de passe, MFA et accès au rôle choisi. Vérifier également un lien expiré et la récupération du mot de passe. Cette étape SMTP/Auth réelle reste à faire ; les tests actuels simulent les invitations.

Si l'adresse possède déjà un compte Supabase, l'API retourne une erreur explicite et n'écrase pas ses droits. La réinvitation d'un compte existant n'est pas incluse. Si le courrier est envoyé mais que l'insertion des droits échoue, le destinataire n'a pas accès à l'administration ; l'interface indique l'échec partiel pour intervention technique.

## Vérifications effectuées

- Tests unitaires invitations : superadmin avec MFA, refus des autres rôles/MFA/origines, entrée invalide, destination exacte et échec d'attribution des droits.
- PGlite : nouveau produit masqué, absence du catalogue public, isolation d'un autre commerçant, publication directe refusée, rôles et MFA contrôlés, file d'attente, approbation puis catalogue visible. Produit existant conservé.
- Client : 144 tests réussis.
- Admin : 179 tests réussis après correction du test d'isolation ; seul le test PostgreSQL natif concurrent n'a pas pu démarrer dans cet environnement root. À exécuter en CI avec un utilisateur non root.
- Build Vite réussi. Les images binaires non téléchargées dans la copie locale ne sont pas modifiées.
- Chromium, parcours commerçant simulé : 375, 390 et 1440 px ; ajout du produit, statut d'attente et absence de débordement horizontal. Ne remplace pas un essai sur Safari iPhone réel.

## Retour arrière SQL (si approuvé)

Le retrait du déclencheur et le rétablissement du routeur précédent arrêtent la mise en attente automatique des futurs produits. **Ne pas publier en masse** les produits encore en attente : ils restent masqués et doivent être examinés individuellement.

```sql
begin;
drop trigger koki_product_review_required on public.koki_records;
drop function koki_private.product_review_required();
drop function koki_private.commerce_admin(text,jsonb);
alter function koki_private.commerce_admin_before_product_review(text,jsonb) rename to commerce_admin;
grant execute on function koki_private.commerce_admin(text,jsonb) to anon,authenticated;
commit;
```
