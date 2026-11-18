-- Environnement Supabase simulé pour rejouer le schéma Koki hors ligne (PostgreSQL local).
do $$ declare r record; begin
 for r in select unnest(array['anon','authenticated','service_role','supabase_admin','authenticator','supabase_auth_admin','supabase_storage_admin','dashboard_user']) n loop
  if not exists(select 1 from pg_roles where rolname=r.n) then execute format('create role %I nologin', r.n); end if;
 end loop; end $$;
create schema if not exists extensions; create schema if not exists auth; create schema if not exists storage;
create schema if not exists vault; create schema if not exists net; create schema if not exists cron; create schema if not exists graphql_public;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pg_stat_statements with schema extensions;
grant usage on schema extensions, auth, storage to anon, authenticated, service_role;
create type auth.factor_type as enum ('totp','webauthn','phone');
create type auth.factor_status as enum ('unverified','verified');
create table auth.users(instance_id uuid, id uuid not null primary key, aud varchar(255), role varchar(255), email varchar(255), encrypted_password varchar(255), email_confirmed_at timestamptz, invited_at timestamptz, confirmation_token varchar(255), confirmation_sent_at timestamptz, recovery_token varchar(255), recovery_sent_at timestamptz, email_change_token_new varchar(255), email_change varchar(255), email_change_sent_at timestamptz, last_sign_in_at timestamptz, raw_app_meta_data jsonb, raw_user_meta_data jsonb, is_super_admin boolean, created_at timestamptz, updated_at timestamptz, phone text default null, phone_confirmed_at timestamptz, phone_change text default '', phone_change_token varchar(255) default '', phone_change_sent_at timestamptz, confirmed_at timestamptz, email_change_token_current varchar(255) default '', email_change_confirm_status smallint default 0, banned_until timestamptz, reauthentication_token varchar(255) default '', reauthentication_sent_at timestamptz, is_sso_user boolean not null default false, deleted_at timestamptz, is_anonymous boolean not null default false);
create table auth.identities(provider_id text not null, user_id uuid not null, identity_data jsonb not null, provider text not null, last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz, email text, id uuid not null default gen_random_uuid() primary key);
create table auth.mfa_factors(id uuid primary key, user_id uuid not null, friendly_name text, factor_type auth.factor_type not null, status auth.factor_status not null, created_at timestamptz not null, updated_at timestamptz not null, secret text, phone text, last_challenged_at timestamptz);
create or replace function auth.uid() returns uuid language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
create or replace function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))::text $$;
create or replace function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim', true), ''), nullif(current_setting('request.jwt.claims', true), ''))::jsonb $$;
create or replace function auth.email() returns text language sql stable as $$ select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email') $$;
grant execute on all functions in schema auth to anon, authenticated, service_role;
create type storage.buckettype as enum ('STANDARD','ANALYTICS','VECTOR');
create table storage.buckets(id text primary key, name text not null, owner uuid, created_at timestamptz default now(), updated_at timestamptz default now(), public boolean default false, avif_autodetection boolean default false, file_size_limit bigint, allowed_mime_types text[], owner_id text, type storage.buckettype not null default 'STANDARD');
create table storage.objects(id uuid not null default gen_random_uuid() primary key, bucket_id text, name text, owner uuid, created_at timestamptz default now(), updated_at timestamptz default now(), last_accessed_at timestamptz default now(), metadata jsonb, path_tokens text[] generated always as (string_to_array(name, '/')) stored, version text, owner_id text, user_metadata jsonb);
alter table storage.objects enable row level security; alter table storage.buckets enable row level security;
grant select, insert, update, delete on storage.objects, storage.buckets to anon, authenticated, service_role;
create or replace function storage.foldername(name text) returns text[] language plpgsql immutable as $$ declare _parts text[]; begin select string_to_array(name, '/') into _parts; return _parts[1:array_length(_parts,1)-1]; end $$;
create or replace function storage.filename(name text) returns text language plpgsql immutable as $$ declare _parts text[]; begin select string_to_array(name, '/') into _parts; return _parts[array_length(_parts,1)]; end $$;
create or replace function storage.extension(name text) returns text language plpgsql immutable as $$ declare _parts text[]; _filename text; begin select string_to_array(name, '/') into _parts; select _parts[array_length(_parts,1)] into _filename; return reverse(split_part(reverse(_filename), '.', 1)); end $$;
grant execute on all functions in schema storage to anon, authenticated, service_role;
create table vault.secrets(id uuid primary key default gen_random_uuid(), name text unique, secret text);
create view vault.decrypted_secrets as select id, name, secret as decrypted_secret from vault.secrets;
create or replace function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000) returns bigint language sql as $$ select 0::bigint $$;
create table cron.job(jobid bigserial primary key, schedule text, command text, jobname text unique);
create or replace function cron.schedule(job_name text, schedule text, command text) returns bigint language plpgsql as $$ declare i bigint; begin insert into cron.job(jobname,schedule,command) values(job_name,schedule,command) on conflict (jobname) do update set schedule=excluded.schedule, command=excluded.command returning jobid into i; return i; end $$;
create or replace function cron.unschedule(job_name text) returns boolean language plpgsql as $$ begin delete from cron.job where jobname=job_name; return found; end $$;
create publication supabase_realtime;
-- Droits par défaut tels qu'en production (schéma public).
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
-- Fonction de la plateforme Supabase (créée par Supabase en production, simulée ici).
create or replace function public.rls_auto_enable() returns event_trigger language plpgsql as $$ begin end $$;
revoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;
