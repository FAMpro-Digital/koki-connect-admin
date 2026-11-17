// Notifications de l'application iPhone : jeton JWT Apple, envoi HTTP/2 et branchement dans l'envoi des notifications.
import test from 'node:test';import assert from 'node:assert/strict';import {generateKeyPairSync,createPublicKey,verify} from 'node:crypto';import {EventEmitter} from 'node:events';
import {apnsJwt,sendApns,tokenGone,apnsConfigured,validToken} from '../api/_apns.js';
import {dispatchHandler} from '../api/notifications-dispatch.js';
const {privateKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
const pem=privateKey.export({type:'pkcs8',format:'pem'});
const env={APNS_KEY_ID:'ABC123DEFG',APNS_TEAM_ID:'TEAM123456',APNS_PRIVATE_KEY:pem,APNS_BUNDLE_ID:'com.kokiconnect.app'};
const jeton='ab'.repeat(32);
test('JWT : ES256 signé avec la clé .p8, identifiant de clé et d’équipe, gardé 50 minutes',()=>{
 const t=apnsJwt(env,1_800_000_000_000);const [h,b,s]=t.split('.');
 assert.deepEqual(JSON.parse(Buffer.from(h,'base64url')),{alg:'ES256',kid:'ABC123DEFG'});assert.equal(JSON.parse(Buffer.from(b,'base64url')).iss,'TEAM123456');
 assert.ok(verify('sha256',Buffer.from(h+'.'+b),{key:createPublicKey(privateKey),dsaEncoding:'ieee-p1363'},Buffer.from(s,'base64url')));
 assert.equal(apnsJwt(env,1_800_000_000_000+49*60000),t);assert.notEqual(apnsJwt(env,1_800_000_000_000+51*60000),t);
 assert.equal(apnsJwt({...env,APNS_PRIVATE_KEY:pem.replace(/\n/g,'\\n')},1_800_000_000_000+51*60000).split('.').length,3,'clé collée sur une ligne acceptée');
});
function fauxHttp2(status,reponse=''){
 const vu={};
 const connect=host=>{vu.host=host;const c=new EventEmitter();c.close=()=>{vu.ferme=true;};
  c.request=headers=>{vu.headers=headers;const r=new EventEmitter();r.setTimeout=()=>{};r.close=()=>{};
   r.end=corps=>{vu.corps=JSON.parse(corps);setImmediate(()=>{r.emit('response',{':status':status});if(reponse)r.emit('data',reponse);r.emit('end');});};return r;};return c;};
 return {vu,connect};
}
test('envoi : serveur de production par défaut, sujet = identifiant de l’app, texte générique',async()=>{
 const {vu,connect}=fauxHttp2(200);const r=await sendApns(env,jeton,{title:'Koki Connect',body:'Une nouvelle information',id:'n1'},{connect});
 assert.deepEqual(r,{status:200,reason:''});assert.equal(vu.host,'https://api.push.apple.com');assert.equal(vu.headers[':path'],'/3/device/'+jeton);
 assert.equal(vu.headers['apns-topic'],'com.kokiconnect.app');assert.equal(vu.headers['apns-push-type'],'alert');assert.match(vu.headers.authorization,/^bearer /);
 assert.deepEqual(vu.corps.aps.alert,{title:'Koki Connect',body:'Une nouvelle information'});assert.ok(vu.ferme);
 const s=fauxHttp2(200);await sendApns({...env,APNS_SANDBOX:'true'},jeton,{title:'a',body:'b',id:'c'},{connect:s.connect});assert.equal(s.vu.host,'https://api.sandbox.push.apple.com');
});
test('jeton refusé ou appareil désinscrit : à oublier ; jeton invalide : aucune requête',async()=>{
 const {connect}=fauxHttp2(410,'{"reason":"Unregistered"}');const r=await sendApns(env,jeton,{title:'a',body:'b',id:'c'},{connect});
 assert.equal(r.status,410);assert.ok(tokenGone(r));assert.ok(tokenGone({status:400,reason:'BadDeviceToken'}));assert.ok(!tokenGone({status:429,reason:'TooManyRequests'}));
 let appel=false;assert.deepEqual(await sendApns(env,'pas-un-jeton',{},{connect:()=>{appel=true;}}),{status:400,reason:'BadDeviceToken'});assert.equal(appel,false);
 assert.equal(validToken(jeton),true);assert.equal(apnsConfigured({}),false);assert.equal(apnsConfigured(env),true);
});
const base={NOTIFICATION_DISPATCH_SECRET:'x'.repeat(40),SUPABASE_URL:'https://test.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test',NOTIFICATION_PUSH_ENABLED:'true',VAPID_PRIVATE_KEY:'test',VAPID_PUBLIC_KEY:'test',VAPID_SUBJECT:'mailto:test@example.com'};
function file(device={id:'dev',token:jeton}){
 const updates=[],suppressions=[],tables=[];
 const db={rpc:async()=>({data:[{id:'job',notification_id:'notification',destination:'apns:dev',channel:'push'}]}),
  from(table){tables.push(table);let supprime=false;return {select(){return this;},eq(){return this;},update(v){updates.push(v);return this;},delete(){supprime=true;suppressions.push(table);return this;},
   single:async()=>({data:{recipient_id:'user'}}),maybeSingle:async()=>({data:table==='koki_apns_devices'?device:null}),then(ok){return Promise.resolve({error:null}).then(ok);}};}};
 return {db,updates,suppressions,tables};
}
const appel=h=>h({method:'POST',headers:{authorization:'Bearer '+base.NOTIFICATION_DISPATCH_SECRET}},{setHeader(){},status(n){this.code=n;return this;},json(v){this.body=v;return this;}});
test('file : destination « apns: » envoyée à Apple, jamais au Web Push ; sans clé Apple, ignorée',async()=>{
 let f=file(),envois=[],web=0;
 await appel(dispatchHandler({env:{...base,...env},client:()=>f.db,sendPush:async()=>{web++;},apns:async(e,t,m)=>{envois.push([t,m.title]);return {status:200,reason:''};}}));
 assert.deepEqual(envois,[[jeton,'Koki Connect']]);assert.equal(web,0);assert.equal(f.updates[0].state,'sent');assert.ok(!f.tables.includes('koki_push_subscriptions'));
 f=file();envois=[];await appel(dispatchHandler({env:base,client:()=>f.db,apns:async()=>{envois.push(1);return {status:200};}}));
 assert.equal(envois.length,0);assert.equal(f.updates[0].state,'skipped');
});
test('file : jeton désinscrit supprimé, échec inscrit sans relance',async()=>{
 const f=file();await appel(dispatchHandler({env:{...base,...env},client:()=>f.db,apns:async()=>({status:410,reason:'Unregistered'})}));
 assert.deepEqual(f.suppressions,['koki_apns_devices']);assert.equal(f.updates[0].state,'failed');
});
