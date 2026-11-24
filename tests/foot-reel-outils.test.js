// Outils des essais réels (supabase/historique/outils/foot-reel) : garde-fou production et TOTP RFC 6238.
import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import {environnement,totp,base32,PRODUCTION_REF} from '../supabase/historique/outils/foot-reel/commun.mjs';

test('garde-fou : la production est refusée, la confirmation est obligatoire',()=>{
 const ok={KOKI_ESSAI_URL:'https://abcdefghijklmnopqrst.supabase.co',KOKI_ESSAI_ANON_KEY:'cle',KOKI_ESSAI_CONFIRME:'projet-essai'};
 assert.equal(environnement(ok).url,ok.KOKI_ESSAI_URL);
 assert.throws(()=>environnement({...ok,KOKI_ESSAI_URL:`https://${PRODUCTION_REF}.supabase.co`}),/PRODUCTION/);
 assert.throws(()=>environnement({...ok,KOKI_ESSAI_CONFIRME:undefined}),/Confirmer/);
 assert.throws(()=>environnement({...ok,KOKI_ESSAI_URL:'https://evil.example.com'}),/inattendue/);
 assert.throws(()=>environnement({}),/requis/);
});
test('TOTP : vecteurs officiels RFC 6238 (SHA-1, 8 chiffres) et base32',()=>{
 const cle=Buffer.from('12345678901234567890');
 for(const [t,code] of [[59,'94287082'],[1111111109,'07081804'],[1111111111,'14050471'],[1234567890,'89005924'],[2000000000,'69279037']])
  assert.equal(totp(null,{cle,temps:t*1000,chiffres:8}),code);
 assert.deepEqual(base32('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),cle);
 assert.equal(totp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',{temps:59000}),'287082');
});
test('scripts réels : aucun secret ni adresse de production en dur, garde-fou appelé',()=>{
 for(const f of ['auth-reel.mjs','realtime-reel.mjs']){const s=readFileSync('supabase/historique/outils/foot-reel/'+f,'utf8');
  assert.doesNotMatch(s,new RegExp(PRODUCTION_REF));assert.doesNotMatch(s,/eyJ[A-Za-z0-9_-]{20,}/);assert.match(s,/environnement\(\)/);}
});
import {expurger,totpFrais,rapporteur} from '../supabase/historique/outils/foot-reel/commun.mjs';
test('preuves expurgées : jetons, clés, e-mails et secrets TOTP masqués',()=>{
 const t=expurger('Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc sb_secret_abcDEF123 editeur@essai.koki.invalid JBSWY3DPEHPK3PXPJBSWY3DP');
 assert.doesNotMatch(t,/eyJ|sb_secret|@essai|JBSWY3/);assert.match(t,/\[JWT\].*\[CLÉ\].*\[e-mail\].*\[SECRET\]/);
});
test('TOTP frais : un même pas de 30 s n’est jamais réutilisé',async()=>{
 let t=60000*1000+29000;const now=()=>t;const s='GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
 const a=await totpFrais(s,now);const attente=totpFrais(s,now);t+=1200;const b=await attente; // attend le pas suivant
 assert.notEqual(a,b);
});
test('rapport : attendu, obtenu, statut et preuve par cas ; « non exécuté » jamais compté réussi',async()=>{
 const R=rapporteur('essai');const log=console.log;console.log=()=>{};
 await R.cas('a','x',async p=>{p('jeton','eyJabcdefghij.eyJabcdefghij.sig');return 'ok';});
 await R.cas('b','y',async()=>'non_execute');await R.cas('c','z',async()=>{throw Error('refus');});console.log=log;
 assert.deepEqual(R.r.map(x=>x.statut),['réussi','non exécuté','échoué']);assert.equal(R.r[0].preuve[0],'jeton [JWT]');
});
test('clé publique : sb_publishable prioritaire, clé secrète refusée, environnement hébergé identifié',()=>{
 const base={KOKI_ESSAI_URL:'https://abcdefghijklmnopqrst.supabase.co',KOKI_ESSAI_CONFIRME:'projet-essai'};
 const e=environnement({...base,KOKI_ESSAI_PUBLISHABLE_KEY:'sb_publishable_x',KOKI_ESSAI_ANON_KEY:'autre'});
 assert.equal(e.type,'publishable');assert.equal(e.cle,'sb_publishable_x');assert.equal(e.heberge,true);assert.equal(e.ref,'abcdefghijklmnopqrst');
 assert.throws(()=>environnement({...base,KOKI_ESSAI_PUBLISHABLE_KEY:'sb_secret_x'}),/clé secrète/);
 const jwtService='x.'+Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url')+'.y';
 assert.throws(()=>environnement({...base,KOKI_ESSAI_ANON_KEY:jwtService}),/clé secrète/);
 assert.equal(environnement({KOKI_ESSAI_URL:'http://127.0.0.1:54321',KOKI_ESSAI_CONFIRME:'projet-essai',KOKI_ESSAI_ANON_KEY:'a.b.c'}).heberge,false);
});
