// Banc d'essai navigateur : monte les écrans Football de l'administration sur le Supabase SIMULÉ local
// (supabase/historique/outils/banc-foot/serveur-supabase.mjs). Jamais utilisé en production.
import {monterFootAdmin} from '/src/foot-admin.js';
const params=new URLSearchParams(location.search),role=params.get('role')||'editor';
async function appel(command,input){
 const r=await fetch('http://127.0.0.1:54321/rest/v1/rpc/koki_foot_admin',{method:'POST',headers:{'Content-Type':'application/json','X-Banc-Role':role},body:JSON.stringify({command,input})});
 const t=await r.text();if(!r.ok){let m=t;try{m=JSON.parse(t).message;}catch{}throw Error(m||('HTTP '+r.status));}return JSON.parse(t);
}
window.__banc={app:monterFootAdmin(document.getElementById('main'),{appel,role})};
