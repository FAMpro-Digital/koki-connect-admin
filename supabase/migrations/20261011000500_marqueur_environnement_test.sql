-- GÉNÉRÉ par scripts/build-local-migrations.mjs — NE PAS MODIFIER À LA MAIN.
-- Source : (marqueur local) · sha256 cc8a0233de7e4ab458155484e7bc0541a4f83bad6eaf456411fde963feeb8b46
-- Usage : Supabase LOCAL uniquement (supabase start / supabase db reset). Jamais « supabase db push ».
-- Marque la base comme environnement de TEST (même marqueur que l'installation TEST).
create table koki_private.test_environment(label text primary key check(label='KOKI TEST'));
alter table koki_private.test_environment enable row level security;
revoke all on koki_private.test_environment from public,anon,authenticated;
insert into koki_private.test_environment values('KOKI TEST');
-- Durcissement optionnel : la fonction système n'existe pas toujours.
do $$ begin if to_regprocedure('public.rls_auto_enable()') is not null then execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';end if;end $$;
