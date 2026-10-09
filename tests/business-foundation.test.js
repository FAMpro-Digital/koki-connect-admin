import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
test('proposition métier : propriétaires, participants, isolation, tarifs et maintien MFA',async()=>{
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
 await pg.exec(await readFile(new URL('../supabase/proposals/commerce-transport-foundation.sql',import.meta.url),'utf8'));
 const ids=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333','44444444-4444-4444-8444-444444444444'];const [admin,client,pro,other]=ids;
 for(const id of ids)await pg.query('insert into auth.users(id) values($1)',[id]);await pg.query("insert into koki_admin_members(user_id,role) values($1,'superadmin')",[admin]);
 const profile=(await pg.query("insert into koki_records(kind,statut,payload,owner_id) values('professionnels','Actif','{\"nom\":\"TEST pro\"}', $1) returning id",[pro])).rows[0].id;
 const product=(await pg.query("insert into koki_records(kind,statut,payload,owner_id) values('produits','Disponible','{\"nom\":\"TEST produit\"}', $1) returning id",[pro])).rows[0].id;
 const order=(await pg.query("insert into koki_records(kind,statut,payload,client_id,provider_id) values('commandes','Commande reçue','{\"nom\":\"TEST commande\"}', $1,$2) returning id",[client,profile])).rows[0].id;
 await pg.query("insert into koki_order_items(order_id,product_id,quantity,unit_price,product_name) values($1,$2,1,500,'TEST produit')",[order,product]);
 async function as(user,aal='aal1',role='authenticated'){await pg.exec('reset role;set role '+role);await pg.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[user||'',JSON.stringify({aal})]);}
 await as(other);assert.equal((await pg.query('select * from koki_records')).rows.length,0);assert.equal((await pg.query('select * from koki_order_items')).rows.length,0);
 await as(client);assert.deepEqual((await pg.query('select id from koki_records')).rows.map(r=>r.id),[order]);assert.equal((await pg.query('select * from koki_order_items')).rows.length,1);
 assert.equal((await pg.query("update koki_records set statut='Livrée' where id=$1 returning id",[order])).rows.length,0);
 await assert.rejects(pg.query("insert into koki_records(kind,statut,payload) values('courses','En attente','{\"nom\":\"TEST\"}')"));
 await as(pro);assert.equal((await pg.query('select * from koki_order_items')).rows.length,1);assert.equal((await pg.query('select * from koki_records')).rows.length,3);
 await as(admin);await assert.rejects(pg.query("insert into koki_transport_rates values('Moto',300,150,true,now())"));
 await as(admin,'aal2');await pg.query("insert into koki_transport_rates values('Moto',300,150,true,now()),('Taxi',500,200,false,now())");
 await as(null,'aal1','anon');assert.deepEqual((await pg.query('select category from koki_transport_rates')).rows.map(r=>r.category),['Moto']);await assert.rejects(pg.query('select * from koki_records'));
 await as(admin,'aal2');assert.equal((await pg.query('select * from koki_records')).rows.length,3);
 await pg.exec('reset role');await pg.query("update koki_records set statut='Suspendu' where id=$1",[profile]);await as(pro);assert.equal((await pg.query('select * from koki_order_items')).rows.length,0);
 }finally{await pg.close();}
});
