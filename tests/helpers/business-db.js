import {readFile} from 'node:fs/promises';
export const testActors={admin:'11111111-1111-4111-8111-111111111111',client:'22222222-2222-4222-8222-222222222222',other:'33333333-3333-4333-8333-333333333333',driver:'44444444-4444-4444-8444-444444444444',merchant:'55555555-5555-4555-8555-555555555555',provider:'66666666-6666-4666-8666-666666666666',editor:'77777777-7777-4777-8777-777777777777'};
export async function setupSupabaseStub(db){
 await db.query(`do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;end $$;create schema auth;create schema storage;
 create table auth.users(id uuid primary key,created_at timestamptz default now());
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
 grant usage on schema auth,storage to anon,authenticated;grant execute on all functions in schema auth to anon,authenticated;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant select,insert,update,delete on storage.objects to authenticated;
 create function storage.foldername(text) returns text[] language sql immutable as $$ select string_to_array($1,'/') $$;`);
}
export async function setupBusinessDB(db){
 await setupSupabaseStub(db);
 for(const name of ['schema.sql','proposals/commerce-transport-foundation.sql','proposals/phase2-transactions.sql'])await db.query(await readFile(new URL('../../supabase/'+name,import.meta.url),'utf8'));
 for(const id of Object.values(testActors))await db.query('insert into auth.users(id) values($1)',[id]);
 await db.query("insert into koki_admin_members(user_id,role) values($1,'superadmin'),($2,'editor')",[testActors.admin,testActors.editor]);
}
export async function actor(db,id,aal='aal1',role='authenticated'){
 await db.query('reset role');await db.query('set role '+role);
 await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id||'',JSON.stringify({aal})]);
}
export async function rpc(db,command,input={}){return (await db.query('select public.koki_business($1,$2::jsonb) as result',[command,JSON.stringify(input)])).rows[0].result;}
export const point={latitude:15.56,longitude:-16.21};export const destination={latitude:15.58,longitude:-16.19};
export async function fixtureBusiness(db){
 const {randomUUID}=await import('node:crypto');const key=()=>randomUUID();
 await actor(db,testActors.driver);const driver=await rpc(db,'register_driver',{request_id:key(),name:'TEST Chauffeur',phone:'+999000000001'});
 const vehicle=await rpc(db,'save_vehicle',{request_id:key(),parent_id:driver.id,name:'TEST Taxi',category:'Taxi',registration:'TEST-001'});
 await actor(db,testActors.merchant);const merchant=await rpc(db,'register_professional',{request_id:key(),name:'TEST Boutique',phone:'+999000000002',profile:'Commerçant'});
 await actor(db,testActors.provider);const provider=await rpc(db,'register_professional',{request_id:key(),name:'TEST Prestataire',phone:'+999000000003',profile:'Prestataire de services'});
 await actor(db,testActors.admin,'aal2');for(const item of [driver,vehicle,merchant,provider])await rpc(db,'admin_review',{request_id:key(),id:item.id,decision:'approve'});
 await rpc(db,'set_rate',{request_id:key(),category:'Taxi',base_fcfa:500,per_km_fcfa:250,active:true});
 await actor(db,testActors.driver);await rpc(db,'driver_position',{request_id:key(),position:point,available:true});
 await actor(db,testActors.merchant);const shop=await rpc(db,'save_shop',{request_id:key(),parent_id:merchant.id,name:'TEST Shop',address:'TEST Koki'});
 const product=await rpc(db,'save_product',{request_id:key(),parent_id:shop.id,name:'TEST Riz',price:500,stock:2});
 await actor(db,testActors.provider);const service=await rpc(db,'save_service',{request_id:key(),parent_id:provider.id,name:'TEST Plomberie',category:'Plomberie',price:null});
 return {driver,vehicle,merchant,provider,shop,product,service};
}
