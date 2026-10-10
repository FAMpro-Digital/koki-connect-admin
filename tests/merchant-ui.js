import {createBusinessClient} from '../src/business-client.js';
import {imagePreview} from '../src/images.js';
import {renderBusinessAdmin} from '../src/business-admin.js';import {can} from '../src/model.js';
const mode=new URLSearchParams(location.search).get('mode')||'public';
const {professional}=await import(mode==='shared'?'/src/business-ui.js':'/public/assets/business/ui.mjs');
const status=document.getElementById('status'),host=document.getElementById('editor');
let records=JSON.parse(sessionStorage.getItem('TEST.merchant.records')||'[]');const persist=()=>sessionStorage.setItem('TEST.merchant.records',JSON.stringify(records));const calls=[];let fail=false;
const user={id:'11111111-2222-4333-8444-555555555555',email:'TEST@example.invalid'};
const db={supabaseUrl:'https://test.supabase.co',auth:{getUser:async()=>({data:{user}})},from:()=>{const filters=[];const q={select:()=>q,eq:(k,v)=>{filters.push([k,v]);return q;},order:()=>q,limit:()=>q,then:f=>Promise.resolve({data:records.filter(r=>filters.every(([k,v])=>r[k]===v))}).then(f)};return q;},storage:{from:()=>({createSignedUrl:async path=>({data:{signedUrl:'https://test.supabase.co/storage/v1/object/sign/koki-media/'+path}})})},rpc:async(name,{command,input})=>{
 calls.push({command,input});if(fail){fail=false;throw Error('TEST réseau interrompu');}
 let row=records[0];if(command==='submit_merchant'){row={id:row?.id||crypto.randomUUID(),kind:'professionnels',owner_id:user.id,revision:(row?.revision||0)+1,statut:'En attente',payload:{nom:input.name,type:input.profile,categorie:input.category,telephone:input.phone,adresse:input.address,horaires:input.hours,description:input.description,localisation:input.location,photos:input.photos,merchant_submission:true}};records=[row];persist();}
 else if(command==='review_merchant'){row.statut=input.decision==='approve'?'Actif':input.decision==='reject'?'Refusé':'Suspendu';row.revision++;persist();}
 return {data:structuredClone(row)};
}};
const api=createBusinessClient(db,{enabled:true,storage:sessionStorage});
window.obtenirPositionActuelle=async()=>({coords:{latitude:15.505,longitude:-15.99}});
const options={upload:async file=>{calls.push({command:'TEST-upload',size:file.size,type:file.type});return user.id+'/'+crypto.randomUUID()+'.jpg';}};
window.merchantTest={calls,failNext:()=>{fail=true;},api};
if(mode==='admin')await renderBusinessAdmin(host,'professionnels',{api,db,list:async()=>records,guard:async()=>{},can,account:{role:'superadmin'},imagePreview,imageURL:path=>api.image(path)});
else await professional(host,api,'commerce',status,options);
window.merchantReady=true;
