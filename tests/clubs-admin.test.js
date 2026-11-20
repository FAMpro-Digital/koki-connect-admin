// Clubs & Académies (administration) : contrat partagé, décisions, branchement, aucune donnée de joueur.
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';
import {decisionsPossibles,motifObligatoire} from '../src/clubs-admin.js';
const sha=f=>createHash('sha256').update(fs.readFileSync(f)).digest('hex');
test('contrat Clubs : identique au site public',()=>{const pub=new URL('../../koki-connect/assets/sport/clubs-contract.js',import.meta.url);
 if(fs.existsSync(pub))assert.equal(sha('src/clubs-contract.js'),sha(pub));assert.ok(globalThis.KokiClubsContract?.ROLES?.responsable);});
test('décisions possibles selon le statut, motif exigé pour refus/suspension/archivage',()=>{
 assert.deepEqual(decisionsPossibles('À valider').map(x=>x[0]),['approve','refuse']);assert.deepEqual(decisionsPossibles('Actif').map(x=>x[0]),['suspend','archive']);
 assert.deepEqual(decisionsPossibles('Suspendu').map(x=>x[0]),['reactivate','archive']);assert.deepEqual(decisionsPossibles('Archivé'),[]);
 assert.ok(motifObligatoire('refuse')&&motifObligatoire('suspend')&&motifObligatoire('archive')&&!motifObligatoire('approve'));});
test('branchement : route clubs, accès depuis Sport, commandes admin uniquement',()=>{
 const app=fs.readFileSync('src/app.js','utf8'),sp=fs.readFileSync('src/sport-admin.js','utf8'),cl=fs.readFileSync('src/clubs-admin.js','utf8');
 assert.match(app,/import \{renderClubs\} from '\.\/clubs-admin\.js';/);assert.match(app,/if\(k==='clubs'\)\{await renderClubs\(main,/);assert.match(app,/clubs:'🎓 Clubs & Académies'/);
 assert.equal((sp.match(/navigate\('clubs'\)/g)||[]).length,2);
 const cmds=[...cl.matchAll(/appel\('([a-z_]+)'/g)].map(m=>m[1]);assert.ok(cmds.length>=7);for(const c of cmds)assert.match(c,/^admin_/,'aucune commande d’espace académie depuis l’administration : '+c);
 assert.doesNotMatch(cl,/players|player_get|guardian|consent|innerHTML/,'aucune donnée de joueur ni HTML injecté');});
test('migrations Clubs : appliquées en production et inscrites dans la référence',()=>{
 const ordre=fs.readFileSync('supabase/historique/reference/ordre.txt','utf8');for(const f of ['20261201000000','20261201000100','20261201000200','20261201000300'])assert.match(ordre,new RegExp(f));
 assert.match(fs.readFileSync('supabase/historique/outils/verifier.sh','utf8'),/empreinte-production-2026-11-20\.txt/);
 for(const f of ['20261201000000_sport_schema','20261201000100_sport_access_rpc','20261201000200_sport_storage','20261201000300_sport_notifications']){
  assert.ok(fs.existsSync('supabase/historique/migrations/'+f+'.sql')&&fs.existsSync('supabase/historique/retour/'+f+'.sql'),f);
  assert.match(fs.readFileSync('supabase/historique/migrations/'+f+'.sql','utf8'),/GARDE/,f+' : garde présente');}
 assert.equal(JSON.parse(fs.readFileSync('vercel.json','utf8')).git.deploymentEnabled['develop/clubs-academies'],false);});
test('contrat Clubs : publié sur l’objet global même quand un bundler définit `module` (bug 20/11/2026)',async()=>{
 const vm=await import('node:vm');const ctx={module:{exports:{}}};ctx.globalThis=ctx;
 vm.runInNewContext(fs.readFileSync('src/clubs-contract.js','utf8'),ctx);
 assert.ok(ctx.KokiClubsContract?.TYPES?.length,'KokiClubsContract doit exister sur l’objet global');
 assert.equal(ctx.module.exports,ctx.KokiClubsContract);
});
