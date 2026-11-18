import test from 'node:test';
import assert from 'node:assert/strict';
import {checkEnvironment,declaredEnvironment,PRODUCTION_REF} from '../src/environment-guard.js';

const PROD='https://'+PRODUCTION_REF+'.supabase.co';
const FAMPRO='https://paegdthtusbwxuarhacb.supabase.co';
const TEST='https://euvxtwmyoihnutifshay.supabase.co';

test('environnement déclaré : KOKI_ENV prioritaire, sinon déduit de Vercel', () => {
 assert.equal(declaredEnvironment({koki:'test',vercel:'production'}),'test');
 assert.equal(declaredEnvironment({vercel:'production'}),'production');
 assert.equal(declaredEnvironment({vercel:'preview'}),'test');
 assert.equal(declaredEnvironment({vercel:'development'}),'test');
 assert.equal(declaredEnvironment({}),null);
 assert.throws(()=>declaredEnvironment({koki:'prod'}),/inconnu/);
});

test('test et local : la production et FAMpro Évents sont refusées', () => {
 for(const environment of ['test','local']){
  assert.throws(()=>checkEnvironment({environment,url:PROD}),/production est interdite/);
  assert.throws(()=>checkEnvironment({environment,url:FAMPRO}),/production est interdite/);
  assert.equal(checkEnvironment({environment,url:TEST}).ref,'euvxtwmyoihnutifshay');
 }
});

test('production : uniquement la base de production', () => {
 assert.equal(checkEnvironment({environment:'production',url:PROD}).ref,PRODUCTION_REF);
 assert.throws(()=>checkEnvironment({environment:'production',url:TEST}),/seule la base de production/);
 assert.throws(()=>checkEnvironment({environment:'production',url:FAMPRO}),/seule la base de production/);
});

test('sans environnement déclaré : comportement inchangé', () => {
 assert.deepEqual(checkEnvironment({environment:null,url:PROD}),{environment:null,ref:PRODUCTION_REF});
});

test('serveur : une préversion Vercel avec la clé de production est bloquée avant tout appel', async () => {
 const {dispatchHandler}=await import('../api/notifications-dispatch.js').catch(e=>{if(process.env.CI||e.code!=='ERR_MODULE_NOT_FOUND')throw e;return {};});
 if(!dispatchHandler)return; // dépendances non installées sur cette machine (toujours exécuté en CI)
 let appels=0;const res={code:0,body:null,setHeader(){},status(c){this.code=c;return this;},json(b){this.body=b;return this;}};
 const env={VERCEL_ENV:'preview',NOTIFICATION_DISPATCH_SECRET:'s',NOTIFICATION_PUSH_ENABLED:'true',VAPID_PRIVATE_KEY:'k',VAPID_PUBLIC_KEY:'k',VAPID_SUBJECT:'mailto:t@example.com',SUPABASE_URL:PROD,SUPABASE_SERVICE_ROLE_KEY:'x'};
 await dispatchHandler({env,client:()=>{appels++;return {};}})({method:'POST',headers:{authorization:'Bearer s'}},res);
 assert.equal(res.code,503);assert.equal(appels,0);
});
