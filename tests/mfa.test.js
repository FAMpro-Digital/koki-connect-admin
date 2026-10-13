import test from 'node:test';import assert from 'node:assert/strict';
import {createMfaManager,factorMetadata} from '../src/mfa.js';

function fixture(){
  let time=0,level='aal2',deny=false;const calls=[];
  const factors=[{id:'old',factor_type:'totp',status:'verified',friendly_name:'Ancien',secret:'DO-NOT-RETAIN'}];
  const ok=data=>({data,error:null});const auth={mfa:{
    listFactors:async()=>ok({all:factors}),getAuthenticatorAssuranceLevel:async()=>ok({currentLevel:level}),
    enroll:async args=>{calls.push(['enroll',args]);factors.push({id:'new',factor_type:'totp',status:'unverified'});return ok({id:'new',totp:{qr_code:'data:image/svg+xml,TEST-ONLY',secret:'DO-NOT-RETAIN'}});},
    challengeAndVerify:async args=>{calls.push(['verify',args.factorId]);if(args.code!=='123456')return {error:{message:'sensitive error'}};factors.find(x=>x.id===args.factorId).status='verified';level='aal2';return ok({access_token:'DO-NOT-RETAIN'});},
    unenroll:async args=>{calls.push(['unenroll',args.factorId]);factors.splice(factors.findIndex(x=>x.id===args.factorId),1);return ok({});}
  }};
  const manager=createMfaManager(auth,async()=>{if(deny)throw Error('Permission refusée.');},()=>time);
  return {manager,calls,factors,setLevel:v=>level=v,setDeny:v=>deny=v,setTime:v=>time=v};
}

test('MFA metadata and enrollment never return raw secrets or auth tokens',async()=>{
  const f=fixture();assert.equal(JSON.stringify(await f.manager.list()).includes('DO-NOT-RETAIN'),false);
  const enrolled=await f.manager.enroll('Nouvel appareil');assert.deepEqual(Object.keys(enrolled).sort(),['id','qr']);
  assert.equal(JSON.stringify(enrolled).includes('DO-NOT-RETAIN'),false);assert.equal(f.calls.some(x=>x[0]==='unenroll'),false);
  assert.deepEqual(factorMetadata({all:[{id:'phone',factor_type:'phone',status:'verified'}]}),[]);
});
test('MFA changes reject aal1, unauthorized accounts and malformed codes',async()=>{
  const f=fixture();f.setLevel('aal1');await assert.rejects(f.manager.enroll('Appareil'),/Double/);
  f.setLevel('aal2');f.setDeny(true);await assert.rejects(f.manager.enroll('Appareil'),/Permission/);
  f.setDeny(false);await assert.rejects(f.manager.verify('old','abcdef',true),/six/);assert.equal(f.calls.length,0);
});
test('verification does not call Supabase without explicit session-change authorization',async()=>{
  const f=fixture();await assert.rejects(f.manager.verify('old','123456'),/explicitement/);assert.equal(f.calls.length,0);
});
test('revocation requires target confirmation and a fresh verified surviving factor',async()=>{
  const f=fixture();await assert.rejects(f.manager.revoke('old','old'),/autre facteur/);
  await f.manager.verify('old','123456',true);await assert.rejects(f.manager.revoke('old','old'),/autre facteur/);
  await f.manager.enroll('Nouveau');await f.manager.verify('new','123456',true);
  await assert.rejects(f.manager.revoke('old','wrong'),/Confirmation/);
  f.setTime(300001);await assert.rejects(f.manager.revoke('old','old'),/autre facteur/);
  assert.equal(f.calls.some(x=>x[0]==='unenroll'),false);
  f.setTime(0);await f.manager.verify('new','123456',true);await f.manager.revoke('old','old');
  assert.deepEqual((await f.manager.list()).map(x=>x.id),['new']);
  await assert.rejects(f.manager.revoke('new','new'),/autre facteur/);
});
test('failed verification clears earlier proof and does not leak SDK errors',async()=>{
  const f=fixture();await f.manager.enroll('Nouveau');await f.manager.verify('new','123456',true);
  await assert.rejects(f.manager.verify('new','000000',true),e=>!e.message.includes('sensitive'));
  await assert.rejects(f.manager.revoke('old','old'),/autre facteur/);
});
test('factor removed elsewhere cannot serve as surviving verification proof',async()=>{
  const f=fixture();await f.manager.enroll('Nouveau');await f.manager.verify('new','123456',true);f.factors.splice(1,1);
  await assert.rejects(f.manager.revoke('old','old'),/autre facteur/);assert.equal(f.calls.some(x=>x[0]==='unenroll'),false);
});
test('clearing session proof prevents revocation after sign-out',async()=>{
  const f=fixture();await f.manager.enroll('Nouveau');await f.manager.verify('new','123456',true);f.manager.clearProof();
  await assert.rejects(f.manager.revoke('old','old'),/autre facteur/);
});
