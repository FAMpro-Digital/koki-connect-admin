// Browser fixture only, never a build entry or connected to a backend.
import '../src/styles.css';
import {renderMfaSettings} from '../src/mfa-settings.js';
import {createMfaManager} from '../src/mfa.js';
const main=document.getElementById('test');
const factors=[{id:'TEST-old-factor',friendly_name:'TEST ancien appareil',factor_type:'totp',status:'verified'}];
const ok=data=>({data,error:null});
const manager=createMfaManager({mfa:{listFactors:async()=>ok({all:factors}),getAuthenticatorAssuranceLevel:async()=>ok({currentLevel:'aal2'}),
enroll:async()=>{factors.push({id:'TEST-new-factor',friendly_name:'TEST nouvel appareil',factor_type:'totp',status:'unverified'});return ok({id:'TEST-new-factor',totp:{qr_code:'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="100" height="100"%3E%3Ctext y="50"%3ETEST%3C/text%3E%3C/svg%3E'}});},
challengeAndVerify:async({factorId,code})=>{if(code!=='123456')return {error:{}};factors.find(x=>x.id===factorId).status='verified';return ok({});},
unenroll:async({factorId})=>{factors.splice(factors.findIndex(x=>x.id===factorId),1);return ok({});}}},async()=>{});
function n(tag,text){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;}
function error(err){document.getElementById('message').textContent=err.message;}
function button(text,fn,cls=''){const b=n('button',text);b.type='button';b.className=cls;b.onclick=()=>Promise.resolve().then(fn).catch(error);return b;}
function field(form,map,key,label,type,unused,value='',required=false){const l=n('label',label),e=n('input');e.name=key;e.type=type;e.required=required;if(type!=='checkbox')e.value=value;l.append(e);form.append(l);map[key]=e;return e;}
function formPanel(){const f=n('form');f.className='forms panel';return f;}
async function refresh(){main.replaceChildren(n('h1','TEST — Paramètres MFA simulés'));await renderMfaSettings(main,manager,{n,button,field,formPanel,error,refresh});}
await refresh();
