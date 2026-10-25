import test from 'node:test';import assert from 'node:assert/strict';
import {dispatchHandler,allowedEndpoint} from '../api/notifications-dispatch.js';
const env={NOTIFICATION_DISPATCH_SECRET:'x'.repeat(40),SUPABASE_URL:'https://test.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test',NOTIFICATION_PUSH_ENABLED:'true',VAPID_PRIVATE_KEY:'test',VAPID_PUBLIC_KEY:'test',VAPID_SUBJECT:'mailto:test@example.com'};
function response(){return {setHeader(){},status(n){this.code=n;return this;},json(v){this.body=v;return this;}};}
function mock({sms=true,phoneConfirmed=true,endpoint='https://fcm.googleapis.com/send/test',channel='push'}={}){
 const updates=[];
 const db={
  rpc:async()=>({data:[{id:'job',notification_id:'notification',destination:'subscription',channel}]}),
  auth:{admin:{getUserById:async()=>({data:{user:{phone:'221771234567',phone_confirmed_at:phoneConfirmed?'2026-01-01':null}}})}},
  from(table){return {
   select(){return this;},eq(){return this;},update(v){updates.push(v);return this;},delete(){return this;},
   single:async()=>({data:{recipient_id:'user'}}),
   maybeSingle:async()=>({data:table==='koki_notification_preferences'?{sms}:{id:'subscription',endpoint,p256dh:'key',auth:'auth'}}),
   then(resolve){return Promise.resolve({error:null}).then(resolve);}
  };}
 };
 return {db,updates};
}

test('endpoint push : refuse redirections vers réseau privé et domaines trompeurs',()=>{for(const u of ['http://fcm.googleapis.com/test','https://127.0.0.1/a','https://fcm.googleapis.com.evil.test/a','https://evil@fcm.googleapis.com/a','https://fcm.googleapis.com:4430/a'])assert.equal(allowedEndpoint(u),false);assert.equal(allowedEndpoint('https://web.push.apple.com/test'),true);});
test('auth obligatoire, aucune file consultée sans secret',async()=>{let touched=false;const handler=dispatchHandler({env,client:()=>{touched=true;}});const res=response();await handler({method:'POST',headers:{}},res);assert.equal(res.code,401);assert.equal(touched,false);});
test('push : message générique, un envoi, résultat conservé',async()=>{const {db,updates}=mock();let count=0;const handler=dispatchHandler({env,client:()=>db,sendPush:async(s,p)=>{count++;assert.equal(JSON.parse(p).title,'Koki Connect');assert.ok(!p.includes('user'));}});const res=response();await handler({method:'POST',headers:{authorization:'Bearer '+env.NOTIFICATION_DISPATCH_SECRET}},res);assert.equal(res.code,200);assert.equal(count,1);assert.equal(updates[0].state,'sent');});
test('push : endpoint privé ignoré sans requête réseau',async()=>{const {db,updates}=mock({endpoint:'https://127.0.0.1/a'});let count=0;await dispatchHandler({env,client:()=>db,sendPush:async()=>{count++;}})({method:'POST',headers:{authorization:'Bearer '+env.NOTIFICATION_DISPATCH_SECRET}},response());assert.equal(count,0);assert.equal(updates[0].state,'skipped');});
test('SMS : consentement et numéro confirmé revérifiés avant chaque envoi',async()=>{for(const settings of [{sms:false},{phoneConfirmed:false}]){const {db,updates}=mock({...settings,channel:'sms'});let calls=0;await dispatchHandler({env:{...env,NOTIFICATION_SMS_ENABLED:'true',TWILIO_ACCOUNT_SID:'ACtest',TWILIO_AUTH_TOKEN:'test',TWILIO_MESSAGING_SERVICE_SID:'MGtest'},client:()=>db,request:async()=>{calls++;}})({method:'POST',headers:{authorization:'Bearer '+env.NOTIFICATION_DISPATCH_SECRET}},response());assert.equal(calls,0);assert.equal(updates[0].state,'skipped');}});
test('SMS : transmission fournisseur et timeout sans relance automatique',async()=>{for(const fail of [false,true]){const {db,updates}=mock({channel:'sms'});let calls=0;await dispatchHandler({env:{...env,NOTIFICATION_SMS_ENABLED:'true',TWILIO_ACCOUNT_SID:'ACtest',TWILIO_AUTH_TOKEN:'test',TWILIO_MESSAGING_SERVICE_SID:'MGtest'},client:()=>db,request:async(url,options)=>{calls++;assert.equal(options.redirect,'error');assert.equal(options.body.get('To'),'+221771234567');if(fail)throw Error('timeout');return {ok:true,json:async()=>({sid:'SMtest'})};}})({method:'POST',headers:{authorization:'Bearer '+env.NOTIFICATION_DISPATCH_SECRET}},response());assert.equal(calls,1);assert.equal(updates[0].state,fail?'failed':'sent');}});
