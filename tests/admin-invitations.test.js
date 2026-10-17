import test from 'node:test';import assert from 'node:assert/strict';
import {invitationHandler} from '../api/invite-admin.js';import {authDestination,recoveryURL} from '../src/auth-destination.js';
const origin='https://admin.example.test';
async function invoke({role='superadmin',aal='aal2',enabled=true,user=true,method='POST',requestOrigin=origin,body={email:' NEW@example.test ',role:'manager'},saveError=false}={}){
 const calls=[];const token='header.'+Buffer.from(JSON.stringify({aal})).toString('base64url')+'.sig';
 const admin={auth:{getUser:async()=>({data:{user:user?{id:'caller'}:null}}),admin:{inviteUserByEmail:async(...args)=>{calls.push(['invite',...args]);return {data:{user:{id:'new'}}};}}},from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{role,enabled}})})}),insert:async row=>{calls.push(['insert',row]);return {error:saveError};}})};
 const res={code:0,setHeader(){},status(code){this.code=code;return this;},json(data){this.data=data;return this;}};
 await invitationHandler({client:()=>admin,env:{SUPABASE_URL:'https://db.example.test',SUPABASE_SERVICE_ROLE_KEY:'server-only',KOKI_ADMIN_ORIGIN:origin}})({method,headers:{origin:requestOrigin,authorization:'Bearer '+token},body},res);return {res,calls};
}
test('invitation : superadmin MFA uniquement, destination exacte et rôle borné',async()=>{
 const {res,calls}=await invoke();assert.equal(res.code,200);assert.deepEqual(calls,[['invite','new@example.test',{redirectTo:origin+'/?action=invite'}],['insert',{user_id:'new',role:'manager',enabled:true}]]);
 for(const options of [{role:'manager'},{role:'editor'},{role:'analyst'},{aal:'aal1'},{enabled:false},{user:false},{requestOrigin:'https://evil.test'},{method:'GET'},{body:{email:'x@y.test',role:'superadmin'}},{body:{email:'invalid',role:'manager'}}]){const r=await invoke(options);assert.ok(r.res.code>=400);assert.equal(r.calls.length,0);}
});
test('échec inscription des droits : ne pas annoncer un accès accordé',async()=>{const {res}=await invoke({saveError:true});assert.equal(res.code,503);assert.match(res.data.error,/accès non accordé/);});
test('liens invitation et récupération, erreurs en query ou fragment',()=>{
 for(const suffix of ['?action=invite','?action=recovery','#type=invite&access_token=token','#type=recovery&access_token=token'])assert.equal(authDestination(origin+'/'+suffix).onboarding,true);
 assert.equal(authDestination(origin+'/').onboarding,false);assert.equal(authDestination(origin+'/?error_code=otp_expired').error,true);assert.equal(authDestination(origin+'/#error=expired').error,true);
 assert.equal(recoveryURL(origin+'/?other=value#secret'),origin+'/?action=recovery');
});
