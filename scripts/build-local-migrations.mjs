// Génère supabase/migrations/ (Supabase local) à partir des sources relues :
// supabase/schema.sql puis les trois propositions, dans l'ordre d'installation validé.
// Les sources restent la référence ; les migrations sont des copies générées, vérifiées par les tests.
//   node scripts/build-local-migrations.mjs          → écrit les fichiers
//   node scripts/build-local-migrations.mjs --check  → échoue si les fichiers ne sont pas à jour
// Aucune connexion réseau, aucune base distante.
import {readFile,writeFile,mkdir,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../',import.meta.url));
export const migrationSources=Object.freeze([
 {name:'20261011000000_garde_projet_vide.sql',file:'supabase/preproduction/fresh-project-check.sql'},
 {name:'20261011000100_schema.sql',file:'supabase/schema.sql'},
 {name:'20261011000200_commerce_transport_foundation.sql',file:'supabase/proposals/commerce-transport-foundation.sql'},
 {name:'20261011000300_phase2_transactions.sql',file:'supabase/proposals/phase2-transactions.sql'},
 {name:'20261011000400_merchant_profiles.sql',file:'supabase/proposals/merchant-profiles.sql'},
 {name:'20261011000450_commerce_modernisation.sql',file:'supabase/proposals/commerce-modernisation.sql'},
 {name:'20261011000470_education_bibliotheque.sql',file:'supabase/proposals/education-bibliotheque.sql'},
 {name:'20261011000480_feed_pagine_quotas.sql',file:'supabase/proposals/feed-pagine-quotas.sql'},
 {name:'20261011000500_marqueur_environnement_test.sql',file:null}
]);
const marker=`-- Marque la base comme environnement de TEST (même marqueur que l'installation TEST).
create table koki_private.test_environment(label text primary key check(label='KOKI TEST'));
alter table koki_private.test_environment enable row level security;
revoke all on koki_private.test_environment from public,anon,authenticated;
insert into koki_private.test_environment values('KOKI TEST');
-- Durcissement optionnel : la fonction système n'existe pas toujours.
do $$ begin if to_regprocedure('public.rls_auto_enable()') is not null then execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';end if;end $$;
`;
// La CLI Supabase exécute chaque migration dans sa propre transaction : begin/commit explicites retirés.
const strip=sql=>sql.replace(/^begin;\s*$/gm,'').replace(/^commit;\s*$/gm,'');
export async function localMigrations(){
 const out=[];
 for(const {name,file} of migrationSources){
  const content=file?await readFile(root+file,'utf8'):marker;
  const sha=createHash('sha256').update(content).digest('hex');
  out.push({name,sql:'-- GÉNÉRÉ par scripts/build-local-migrations.mjs — NE PAS MODIFIER À LA MAIN.\n-- Source : '+(file||'(marqueur local)')+' · sha256 '+sha+'\n-- Usage : Supabase LOCAL uniquement (supabase start / supabase db reset). Jamais « supabase db push ».\n'+strip(content)});
 }
 return out;
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const dir=root+'supabase/migrations/';await mkdir(dir,{recursive:true});
 const expected=await localMigrations(),check=process.argv.includes('--check');
 const present=(await readdir(dir)).filter(f=>f.endsWith('.sql')).sort();
 const stale=[];
 for(const m of expected){let current=null;try{current=await readFile(dir+m.name,'utf8');}catch{}if(current!==m.sql){stale.push(m.name);if(!check)await writeFile(dir+m.name,m.sql);}}
 const extra=present.filter(f=>!expected.some(m=>m.name===f));
 if(check){if(stale.length||extra.length){console.error('Migrations locales à régénérer : '+[...stale,...extra.map(x=>x+' (inattendu)')].join(', '));process.exit(1);}console.log('Migrations locales à jour ('+expected.length+').');}
 else console.log((stale.length?'Migrations régénérées : '+stale.join(', '):'Migrations déjà à jour.')+(extra.length?'\nFichiers inattendus (non supprimés) : '+extra.join(', '):''));
}
