-- Rattrapage : table des photos multiples des publications, créée à la main en production (aucun fichier source).
-- Définition relevée en production le 18/11/2026 (lecture seule).
create table public.koki_content_images(
 id uuid default gen_random_uuid() not null,
 content_id uuid not null,
 storage_path text not null,
 display_order integer default 0 not null,
 created_at timestamp with time zone default now() not null
);
alter table public.koki_content_images add constraint koki_content_images_pkey PRIMARY KEY (id);
alter table public.koki_content_images add constraint koki_content_images_content_id_fkey FOREIGN KEY (content_id) REFERENCES koki_contents(id) ON DELETE CASCADE;
alter table public.koki_content_images add constraint koki_content_images_display_order_check CHECK ((display_order >= 0));
alter table public.koki_content_images add constraint koki_content_images_storage_path_check CHECK ((storage_path ~ '^[a-f0-9-]+/[a-f0-9-]+\\.(jpg|png|webp)$'::text));
CREATE INDEX koki_content_images_content_order ON public.koki_content_images USING btree (content_id, display_order);
alter table public.koki_content_images enable row level security;
create policy koki_content_images_admin_write on public.koki_content_images as permissive for all to authenticated using ((EXISTS ( SELECT 1
   FROM koki_admin_members m
  WHERE ((m.user_id = auth.uid()) AND m.enabled AND (m.role = ANY (ARRAY['superadmin'::text, 'editor'::text])))))) with check ((EXISTS ( SELECT 1
   FROM koki_admin_members m
  WHERE ((m.user_id = auth.uid()) AND m.enabled AND (m.role = ANY (ARRAY['superadmin'::text, 'editor'::text]))))));
create policy koki_content_images_public_read on public.koki_content_images as permissive for select to anon, authenticated using ((EXISTS ( SELECT 1
   FROM koki_contents c
  WHERE ((c.id = koki_content_images.content_id) AND (c.statut = 'publié'::text) AND (c.publication <= now())))));
