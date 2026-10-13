// Génère le paquet de mise à jour de la PRODUCTION Koki Connect (phases 2 à 6) à partir des sources relues.
//   node scripts/prepare-production-phases.mjs          → écrit supabase/production/koki-production-phases-2-6.sql
//   node scripts/prepare-production-phases.mjs --check  → échoue si le fichier versionné n'est pas à jour
// Aucune connexion réseau. Une seule transaction : toute erreur annule tout.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../',import.meta.url));
export const PRODUCTION='qsbmzzbiztfqysstepxm';
export const sources=Object.freeze(['supabase/proposals/commerce-transport-foundation.sql','supabase/proposals/phase2-transactions.sql','supabase/proposals/merchant-profiles.sql','supabase/proposals/commerce-modernisation.sql']);
// Fiche d'essai « Tg » sans compte (11/10/2026), dont la suppression a été décidée par le propriétaire le 13/10/2026.
export const ficheEssai='b381d81b-2fc8-4559-b0b4-5251813daffa';
const strip=sql=>sql.replace(/^begin;\s*$/gm,'').replace(/^commit;\s*$/gm,'');
export async function paquet(){
 const parts=[];
 for(const f of sources){const sql=await readFile(root+f,'utf8');parts.push('-- SOURCE : '+f+' · sha256 '+createHash('sha256').update(sql).digest('hex')+'\n'+strip(sql));}
 return `-- KOKI CONNECT — MISE À JOUR DE LA PRODUCTION ${PRODUCTION} : phases 2 à 6 (Commerces, Transport, espace professionnel).
-- GÉNÉRÉ par scripts/prepare-production-phases.mjs — NE PAS MODIFIER À LA MAIN.
-- Une seule transaction : en cas d'erreur, rien n'est modifié. Aucune donnée fictive, aucun marqueur TEST.
begin;
-- GARDE : n'accepte que l'état vérifié de la production (schéma initial + Bibliothèque, aucune phase 2 à 6).
do $$ begin
 if current_setting('server_version_num')::integer<170000 then raise exception 'GARDE : PostgreSQL 17 requis';end if;
 if to_regclass('koki_private.test_environment') is not null then raise exception 'GARDE : base de TEST, paquet réservé à la production';end if;
 if to_regprocedure('public.koki_business(text,jsonb)') is not null or to_regclass('public.koki_order_items') is not null then raise exception 'GARDE : phases déjà installées';end if;
 if to_regclass('public.koki_records') is null or to_regprocedure('koki_private.allowed(text)') is null then raise exception 'GARDE : schéma initial absent';end if;
 if to_regprocedure('koki_private.livre_gratuit_publie(text)') is null then raise exception 'GARDE : Bibliothèque non installée';end if;
 if exists(select 1 from public.koki_records where id<>'${ficheEssai}') then raise exception 'GARDE : fiches métier inattendues, rapprochement nécessaire';end if;
end $$;
-- Archive privée des éléments retirés par une migration (lecture réservée au propriétaire de la base).
create table koki_private.migration_archive(id uuid primary key default gen_random_uuid(),archived_at timestamptz not null default now(),reason text not null,source_table text not null,data jsonb not null);
alter table koki_private.migration_archive enable row level security;
revoke all on koki_private.migration_archive from public,anon,authenticated;
insert into koki_private.migration_archive(reason,source_table,data)
 select 'Fiche d''essai sans compte supprimée avant les phases 2 à 6 (décision du propriétaire, 13/10/2026)','public.koki_records',to_jsonb(r)
 from public.koki_records r where r.id='${ficheEssai}';
delete from public.koki_records where id='${ficheEssai}';

${parts.join('\n')}
-- Durcissement : public.koki_statistics() réservé aux comptes connectés (la fonction refusait déjà en interne).
revoke execute on function public.koki_statistics() from anon;
notify pgrst, 'reload schema';
commit;
`;
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const out=root+'supabase/production/koki-production-phases-2-6.sql',sql=await paquet();
 if(process.argv.includes('--check')){let cur=null;try{cur=await readFile(out,'utf8');}catch{}if(cur!==sql){console.error('Paquet production à régénérer.');process.exit(1);}console.log('Paquet production à jour.');}
 else{await mkdir(root+'supabase/production',{recursive:true});await writeFile(out,sql);console.log('Écrit : '+out+' ('+sql.length+' caractères, sha256 '+createHash('sha256').update(sql).digest('hex')+')');}
}
