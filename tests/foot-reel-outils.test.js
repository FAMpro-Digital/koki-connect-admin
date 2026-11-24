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
