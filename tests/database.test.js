import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
test('RLS, MFA, rôles, programmation et journal : exécution SQL',async()=>{
const pg=new PGlite();try{
await pg.exec(`create role anon;create role authenticated;create schema auth;create schema storage;
create table auth.users(id uuid primary key,created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
grant usage on schema auth,storage to anon,authenticated;grant execute on all functions in schema auth to anon,authenticated;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant select,insert,update,delete on storage.objects to authenticated;
create function storage.foldername(text) returns text[] language sql immutable as $$ select string_to_array($1,'/') $$;`);
await pg.exec(await readFile(new URL('../supabase/schema.sql',import.meta.url),'utf8'));
const admin='11111111-1111-4111-8111-111111111111',editor='22222222-2222-4222-8222-222222222222',manager='33333333-3333-4333-8333-333333333333',outsider='44444444-4444-4444-8444-444444444444';
await pg.exec(`insert into auth.users(id) values('${admin}'),('${editor}'),('${manager}'),('${outsider}');insert into koki_admin_members(user_id,role) values('${admin}','superadmin'),('${editor}','editor'),('${manager}','manager');`);
async function as(role,user,aal){await pg.exec(`reset role;set role ${role};select set_config('request.jwt.claim.sub','${user||''}',false);select set_config('request.jwt.claims','${JSON.stringify({aal})}',false);`);}
const insert=`insert into koki_contents(type,titre,resume,statut,publication) values('Actualités','Test','Texte','brouillon',now()-interval '1 hour') returning id`;
await as('anon',null,'aal1');assert.equal((await pg.query('select * from koki_contents')).rows.length,0);await assert.rejects(pg.query(insert));
await as('authenticated',admin,'aal1');await assert.rejects(pg.query(`insert into storage.objects(bucket_id,name) values('koki-media','${admin}/image.jpg')`));await assert.rejects(pg.query(insert));await assert.rejects(pg.query('select koki_statistics()'));
await as('authenticated',outsider,'aal2');await assert.rejects(pg.query(insert));await assert.rejects(pg.query('select koki_statistics()'));
await as('authenticated',editor,'aal2');await pg.query(`insert into storage.objects(bucket_id,name) values('koki-media','${editor}/11111111-1111-4111-8111-111111111111.jpg')`);const id=(await pg.query(insert)).rows[0].id;await assert.rejects(pg.query(`insert into koki_records(kind,statut,payload) values('produits','Disponible','{"nom":"Riz"}')`));await assert.rejects(pg.query(`update koki_admin_members set role='superadmin' where user_id='${editor}'`));
await pg.query(`update koki_contents set statut='publié' where id='${id}'`);await pg.query(`insert into koki_contents(type,titre,resume,statut,publication) values('Actualités','Future','Texte','publié',now()+interval '1 day')`);
await pg.query(`insert into koki_contents(type,titre,resume,statut,publication,fin) values('Publicités','Expired','Texte','publié',now()-interval '2 days',now()-interval '1 day')`);
await as('anon',null,'aal1');assert.deepEqual((await pg.query('select titre from koki_contents')).rows.map(x=>x.titre),['Test']);assert.equal((await pg.query('select koki_public_feed() as feed')).rows[0].feed.contenus.length,1);await pg.exec('reset role;grant select on storage.objects to anon;set role anon;');assert.equal((await pg.query('select * from storage.objects')).rows.length,0);
await as('authenticated',manager,'aal2');await assert.rejects(pg.query(insert));await pg.query(`insert into koki_records(kind,statut,payload) values('produits','Disponible','{"nom":"Riz","stock":2,"prix":500}')`);await assert.rejects(pg.query(`insert into koki_records(kind,statut,payload) values('produits','Disponible','{"nom":"Riz","stock":-2}')`));assert.equal((await pg.query('select * from koki_audit')).rows.length,0);
await as('authenticated',admin,'aal2');assert.ok((await pg.query('select * from koki_audit')).rows.length>=5);await assert.rejects(pg.query(`delete from koki_audit`));const stats=(await pg.query('select koki_statistics() as stats')).rows[0].stats;assert.equal(stats['Actualités publiées'],1);assert.equal(stats['Utilisateurs inscrits'],4);assert.equal(stats['Revenus FCFA'],null);
await pg.exec(`reset role;update koki_admin_members set enabled=false where user_id='${admin}';`);await as('authenticated',admin,'aal2');await assert.rejects(pg.query('select koki_statistics()'));await assert.rejects(pg.query(insert));
}finally{await pg.close();}
});
