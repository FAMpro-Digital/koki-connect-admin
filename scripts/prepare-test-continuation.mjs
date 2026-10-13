// Paquet de POURSUITE pour le projet Supabase TEST euvxtwmyoihnutifshay (état vérifié en lecture seule le 11/10/2026 :
// schema.sql + commerce-transport-foundation.sql installés, base vide). Ce script ne se connecte à rien :
// il assemble des fichiers SQL locaux en une seule transaction gardée et écrit le paquet et son manifeste.
import {readFile,writeFile} from 'node:fs/promises';import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';

export const TEST_PROJECT_REF='euvxtwmyoihnutifshay';
export const BLOCKED_PROJECT_REFS=['qsbmzzbiztfqysstepxm','paegdthtusbwxuarhacb'];
export const BUNDLE_PATH='supabase/preproduction/koki-test-poursuite-phase6.sql';
export const MANIFEST_PATH='supabase/preproduction/koki-test-poursuite-phase6.manifest.json';
export const SOURCES=['supabase/proposals/phase2-transactions.sql','supabase/proposals/merchant-profiles.sql','supabase/proposals/commerce-modernisation.sql'];

const root=fileURLToPath(new URL('../',import.meta.url));
const sha=t=>createHash('sha256').update(t).digest('hex');

export const GUARD=`-- GARDE : n'accepte que l'état exact du projet TEST (schéma initial + fondation, aucune donnée, pas encore de routeur métier).
-- Toute autre base (production avec comptes, fiches, contenus ou photos ; projet déjà installé ; projet incomplet) est refusée sans modification.
do $$ begin
 if current_setting('server_version_num')::integer<170000 then raise exception 'GARDE : PostgreSQL 17 requis';end if;
 if to_regclass('koki_private.test_environment') is not null then raise exception 'GARDE : poursuite déjà appliquée';end if;
 if to_regprocedure('public.koki_business(text,jsonb)') is not null then raise exception 'GARDE : routeur métier déjà présent, état inattendu';end if;
 if to_regclass('public.koki_records') is null or to_regclass('public.koki_order_items') is null or to_regclass('public.koki_transport_rates') is null then raise exception 'GARDE : schéma initial ou fondation absents';end if;
 if exists(select 1 from auth.users) or exists(select 1 from public.koki_records) or exists(select 1 from public.koki_contents)
  or exists(select 1 from public.koki_users) or exists(select 1 from public.koki_admin_members) or exists(select 1 from storage.objects)
 then raise exception 'GARDE : base non vide, installation refusée (production ?)';end if;
end $$;`;

export const FINAL=`-- Marqueur TEST (exigé par les données fictives) et durcissement constaté sur TEST :
-- anon pouvait exécuter public.koki_statistics() (droit par défaut Supabase ; la fonction refusait déjà en interne).
create table koki_private.test_environment(label text primary key check(label='KOKI TEST'));
alter table koki_private.test_environment enable row level security;
revoke all on koki_private.test_environment from public,anon,authenticated;
insert into koki_private.test_environment values('KOKI TEST');
revoke execute on function public.koki_statistics() from anon;
do $$ begin if to_regprocedure('public.rls_auto_enable()') is not null then execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';end if;end $$;
notify pgrst, 'reload schema';`;

export async function continuationBundle(){
 const parts=[GUARD],files=[];
 for(const file of SOURCES){const content=await readFile(root+file,'utf8');files.push({file,sha256:sha(content)});parts.push('-- SOURCE : '+file+'\n'+content.replace(/^begin;\s*$/gm,'').replace(/^commit;\s*$/gm,''));}
 parts.push(FINAL);
 const sql=`-- KOKI CONNECT — POURSUITE D'INSTALLATION, PROJET SUPABASE TEST UNIQUEMENT : ${TEST_PROJECT_REF}
-- GÉNÉRÉ par scripts/prepare-test-continuation.mjs — NE PAS MODIFIER À LA MAIN. Jamais sur ${BLOCKED_PROJECT_REFS.join(' ni ')}.
-- Une seule transaction : en cas d'erreur, rien n'est modifié. Retour arrière : supabase/preproduction/retour-arriere-phase6.sql.
begin;
${parts.join('\n')}
commit;
`;
 const manifest={target:TEST_PROJECT_REF,blocked:BLOCKED_PROJECT_REFS,remoteApplied:false,bundle:BUNDLE_PATH,bundleSha256:sha(sql),files,
  expectedBaseline:'schema.sql + proposals/commerce-transport-foundation.sql, base vide',rollback:'supabase/preproduction/retour-arriere-phase6.sql'};
 return {sql,manifest:JSON.stringify(manifest,null,2)+'\n'};
}

if(process.argv[1]===fileURLToPath(import.meta.url)){
 const {sql,manifest}=await continuationBundle();
 await writeFile(root+BUNDLE_PATH,sql);await writeFile(root+MANIFEST_PATH,manifest);
 console.log('Paquet de poursuite TEST écrit ('+sql.length+' octets) ; aucune connexion distante, aucune migration exécutée.');
}

// ---------------------------------------------------------------------------------------------
// RETOUR ARRIÈRE : ramène TEST à l'état vérifié avant poursuite (schema.sql + fondation), sans perte de données.
// Les définitions d'origine sont extraites de supabase/schema.sql pour éviter toute divergence.
export const ROLLBACK_PATH='supabase/preproduction/retour-arriere-phase6.sql';
export const ADDED_FUNCTIONS=['public.koki_business(text,jsonb)','koki_private.commerce_admin(text,jsonb)','koki_private.commerce_admin_view(public.koki_records)',
 'koki_private.commerce_publie(public.koki_records)','koki_private.commerce_parent_actif(public.koki_records)','koki_private.commerce_business(text,jsonb)',
 'koki_private.commerce_sensibles(jsonb)','koki_private.my_media_folder()','koki_private.commerce_catalog()','koki_private.commerce_int(jsonb,text,bigint,text)',
 'koki_private.commerce_village(jsonb)','koki_private.commerce_phone(jsonb,text)','koki_private.commerce_photos(jsonb)','koki_private.merchant_business(text,jsonb)',
 'koki_private.business_image_unreferenced(text)','koki_private.business_participant_image(text)','koki_private.business_public_image(text)','koki_private.business(text,jsonb)',
 'koki_private.business_owned_image(text)','koki_private.business_can_read(public.koki_records)','koki_private.business_distance(jsonb,jsonb)','koki_private.business_point(jsonb)',
 'koki_private.business_text(jsonb,text,integer,integer)','koki_private.business_keys_allowed(jsonb,text[])','koki_private.business_item_relation()','koki_private.business_relations()'];
export const ADDED_POLICIES=[['storage.objects','business_media_alias_delete'],['storage.objects','business_media_alias_insert'],['storage.objects','business_media_alias_read'],
 ['storage.objects','business_media_insert'],['storage.objects','business_media_owner_delete'],['storage.objects','business_media_owner_read'],['storage.objects','business_media_participant_read'],
 ['storage.objects','business_media_public_read'],['storage.objects','editorial_admin_media_read'],['storage.objects','media_reference_guard'],
 ['public.koki_localites','localites_admin_insert'],['public.koki_localites','localites_admin_update'],['public.koki_localites','localites_public_read'],
 ['public.koki_records','records_admin_business_read'],['public.koki_users','users_self_read']];
export const ADDED_TABLES=['koki_private.business_keys','koki_private.ride_quotes','koki_private.nearby_lookups','koki_private.media_folders','koki_private.test_environment','public.koki_localites'];

function extract(source,start,end){const i=source.indexOf(start);if(i<0)throw Error('Définition d\'origine introuvable : '+start);const j=source.indexOf(end,i);if(j<0)throw Error('Fin introuvable : '+start);return source.slice(i,j+end.length);}

export async function rollbackScript(){
 const schema=await readFile(root+'supabase/schema.sql','utf8');
 const statusConstraint=extract(schema,'alter table public.koki_records add constraint koki_record_status check(','));');
 const statistics=extract(schema,'create function public.koki_statistics()','end $$;').replace('create function','create or replace function');
 const recordsRead=extract(schema,'create policy records_read on public.koki_records',';');
 const mediaRead=extract(schema,'create policy koki_media_read on storage.objects',';');
 const villages=(await readFile(root+'supabase/proposals/commerce-modernisation.sql','utf8')).match(/insert into public\.koki_localites\(nom,ordre,source\) values([\s\S]*?);/)[1];
 const villageRows=[...villages.matchAll(/\('([^']+)',(\d+),'([^']+)'\)/g)].map(m=>`('${m[1].replaceAll("'","''")}',${m[2]},'${m[3]}')`);if(villageRows.length!==10)throw Error('Liste des villages inattendue');
 const sql=`-- KOKI CONNECT — RETOUR ARRIÈRE DE LA POURSUITE PHASE 6, PROJET SUPABASE TEST UNIQUEMENT : ${TEST_PROJECT_REF}
-- GÉNÉRÉ par scripts/prepare-test-continuation.mjs — NE PAS MODIFIER À LA MAIN. Jamais sur ${BLOCKED_PROJECT_REFS.join(' ni ')}.
-- Ramène la base à l'état vérifié le 11/10/2026 (schema.sql + fondation) : même empreinte (supabase/preproduction/empreinte.sql).
-- Aucune donnée n'est supprimée : le script REFUSE de s'exécuter si une table ajoutée contient des données créées après l'installation,
-- ou si une fiche existante n'est plus compatible avec les règles d'origine. Comptes, contenus, tarifs, journal et photos sont conservés.
-- Une seule transaction : en cas d'erreur, rien n'est modifié.
begin;
do $$ declare n bigint; begin
 if to_regclass('koki_private.test_environment') is null then raise exception 'GARDE : base non marquée « KOKI TEST » (production ou poursuite non appliquée) : retour arrière refusé';end if;
 if not exists(select 1 from koki_private.test_environment where label='KOKI TEST') then raise exception 'GARDE : base non marquée « KOKI TEST » (production ou poursuite non appliquée) : retour arrière refusé';end if;
 if to_regprocedure('public.koki_business(text,jsonb)') is null then raise exception 'GARDE : routeur métier absent, état inattendu';end if;
 select count(*) into n from koki_private.business_keys;if n>0 then raise exception 'GARDE : % clé(s) d''opération créées après installation : exporter et décider avant retour arrière',n;end if;
 select count(*) into n from koki_private.ride_quotes;if n>0 then raise exception 'GARDE : % devis de course créés après installation',n;end if;
 select count(*) into n from koki_private.nearby_lookups;if n>0 then raise exception 'GARDE : % recherche(s) de proximité enregistrées après installation',n;end if;
 select count(*) into n from koki_private.media_folders;if n>0 then raise exception 'GARDE : % dossier(s) photo anonymes attribués après installation',n;end if;
 if (select count(*) from public.koki_localites)<>${villageRows.length}
  or exists(select 1 from public.koki_localites l where not l.actif or l.type<>'À préciser'
   or not exists(select 1 from (values ${villageRows.join(',')}) v(nom,ordre,source) where v.nom=l.nom and v.ordre=l.ordre and v.source=l.source))
  then raise exception 'GARDE : la liste des villages a été modifiée après installation';end if;
 if exists(select 1 from public.koki_records where not (
${statusConstraint.replace('alter table public.koki_records add constraint koki_record_status check(','').replace(/\);$/,'')}
 )) then raise exception 'GARDE : des fiches utilisent des statuts introduits par la poursuite : retour arrière refusé sans perte';end if;
end $$;
-- 1. Politiques ajoutées (Storage et tables)
${ADDED_POLICIES.map(([t,p])=>`drop policy ${p} on ${t};`).join('\n')}
-- 2. Déclencheurs, contraintes et index ajoutés
drop trigger business_relations on public.koki_records;
drop trigger business_item_relation on public.koki_order_items;
alter table public.koki_records drop constraint koki_business_owner, drop constraint business_required_links, drop constraint business_source_reserved;
drop index public.koki_commerce_unique_name, public.koki_client_one_active_ride, public.koki_driver_one_active_ride, public.koki_driver_account, public.koki_professional_account;
-- 3. Fonctions ajoutées (routeur public en premier)
${ADDED_FUNCTIONS.map(f=>`drop function ${f};`).join('\n')}
-- 4. Tables ajoutées (vérifiées vides ou identiques à l'installation ci-dessus)
${ADDED_TABLES.map(t=>`drop table ${t};`).join('\n')}
-- 5. Définitions d'origine (extraites de supabase/schema.sql)
alter table public.koki_records drop constraint koki_record_status;
${statusConstraint}
${recordsRead}
${mediaRead}
${statistics}
-- 6. Droits d'origine, y compris le droit par défaut Supabase constaté sur TEST avant poursuite
grant insert,update,delete on public.koki_records to authenticated;
grant insert,update,delete on public.koki_transport_rates to authenticated;
revoke usage on schema koki_private from anon;
grant execute on function public.koki_statistics() to anon;
notify pgrst, 'reload schema';
commit;
`;
 return sql;
}

if(process.argv[1]===fileURLToPath(import.meta.url)){await writeFile(root+ROLLBACK_PATH,await rollbackScript());console.log('Script de retour arrière TEST écrit ; non exécuté.');}
