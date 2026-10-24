import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {verifierCible,PALIERS,SEUILS,REFERENCES_PRODUCTION} from '../loadtests/garde.js';
test('garde des tests de charge : la production est toujours refusée',()=>{
 for(const url of ['https://qsbmzzbiztfqysstepxm.supabase.co','https://QSBMZZBIZTFQYSSTEPXM.supabase.co/rest/v1','http://127.0.0.1.qsbmzzbiztfqysstepxm.supabase.co'])
  assert.throws(()=>verifierCible(url,{KOKI_ENV:'TEST',KOKI_HOTE_TEST:'qsbmzzbiztfqysstepxm.supabase.co'}),/production Koki/);
 assert.deepEqual([...REFERENCES_PRODUCTION],['qsbmzzbiztfqysstepxm']);
});
test('garde : local accepté, hôte distant seulement déclaré TEST, absent ou invalide refusé',()=>{
 assert.equal(verifierCible('http://127.0.0.1:54321/'),'http://127.0.0.1:54321');
 assert.equal(verifierCible('http://localhost:54321'),'http://localhost:54321');
 assert.throws(()=>verifierCible('https://autre.supabase.co'),/hôte distant non autorisé/);
 assert.throws(()=>verifierCible('https://autre.supabase.co',{KOKI_ENV:'TEST',KOKI_HOTE_TEST:'un-autre.supabase.co'}),/non autorisé/);
 assert.equal(verifierCible('https://test-isole.supabase.co',{KOKI_ENV:'TEST',KOKI_HOTE_TEST:'test-isole.supabase.co'}),'https://test-isole.supabase.co');
 assert.throws(()=>verifierCible('https://koki-prod.example',{KOKI_ENV:'TEST',KOKI_HOTE_TEST:'koki-prod.example'}),/production/);
 for(const v of [undefined,'','pas une url','ftp://127.0.0.1'])assert.throws(()=>verifierCible(v),/invalide/);
});
test('paliers et seuils d\'arrêt',async()=>{
 assert.deepEqual([...PALIERS],[10,50,100,250,500]);assert.equal(SEUILS.erreurs,0.05);assert.equal(SEUILS.p95_ms,2000);
 const k6=await readFile(new URL('../loadtests/flux-public.js',import.meta.url),'utf8');
 assert.match(k6,/verifierCible\(__ENV\.BASE_URL, __ENV\)/);assert.match(k6,/abortOnFail: true/);assert.match(k6,/sb_publishable_/);
 const sh=await readFile(new URL('../loadtests/run-paliers.sh',import.meta.url),'utf8');
 assert.match(sh,/for palier in 10 50 100 250 500/);assert.match(sh,/exit "\$code"/);
});
