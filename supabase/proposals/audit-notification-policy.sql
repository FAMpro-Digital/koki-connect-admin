-- Évaluer les claims une fois par requête, sans modifier les droits.
alter policy notification_preferences_own on public.koki_notification_preferences using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()) and not coalesce(((select auth.jwt())->>'is_anonymous')::boolean,false));
