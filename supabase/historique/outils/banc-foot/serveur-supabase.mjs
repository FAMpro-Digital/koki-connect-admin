// Banc d'essai navigateur du module Football : imite les points RPC de Supabase (PostgREST) devant une base
// PostgreSQL LOCALE. N'écoute que sur 127.0.0.1. Ne se connecte jamais à Supabase.
//   POST /rest/v1/rpc/koki_foot_public  → rôle anon
//   POST /rest/v1/rpc/koki_foot_admin   → rôle authenticated, jeton simulé (X-Banc-Role : editor | superadmin | habitant), aal2
//   POST /rest/v1/rpc/koki_public_feed  → flux vide (le reste du site public reste fonctionnel)
//   POST /__banc/panne {mode:"503"|"coupure"|"lent"|"aucune"} → simule une panne réseau ou serveur
import {createServer} from 'node:http';import {execFile} from 'node:child_process';
const BASE=process.env.BANC_BASE||'koki_foot_banc',PORT=Number(process.env.BANC_PORT||54321);
const UTILISATEURS={editor:'b0000000-0000-4000-8000-0000000000e1',superadmin:'b0000000-0000-4000-8000-0000000000a1',habitant:'b0000000-0000-4000-8000-0000000000c1'};
let panne='aucune';
function psql(sql,vars){return new Promise((ok,ko)=>{const args=['-n','-u','postgres','psql','-X','-q','-At','-v','ON_ERROR_STOP=1','-d',BASE];
 for(const [k,v] of Object.entries(vars))args.push('-v',k+'='+v);
 const p=execFile('sudo',args,{maxBuffer:32e6},(e,out,err)=>e?ko(Error(String(err||e.message).replace(/^.*?ERROR:\s*/s,'').split('\n')[0])):ok(out.trim().split('\n').pop()));p.stdin.end(sql);});}
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'apikey, authorization, content-type, x-banc-role, x-client-info','Access-Control-Allow-Methods':'POST, GET, OPTIONS'};
function envoyer(res,code,corps){res.writeHead(code,{...cors,'Content-Type':'application/json'});res.end(typeof corps==='string'?corps:JSON.stringify(corps));}
createServer(async(req,res)=>{
 if(req.method==='OPTIONS'){res.writeHead(204,cors);res.end();return;}
 let corps='';for await(const c of req)corps+=c;
 const url=new URL(req.url,'http://127.0.0.1');
 if(url.pathname==='/__banc/panne'){panne=JSON.parse(corps||'{}').mode||'aucune';envoyer(res,200,{panne});return;}
 if(panne==='coupure'){req.socket.destroy();return;}
 if(panne==='503'){envoyer(res,503,{message:'Service indisponible (simulé)'});return;}
 if(panne==='lent')await new Promise(r=>setTimeout(r,12000));
 const m=/^\/rest\/v1\/rpc\/([a-z_]+)$/.exec(url.pathname);
 if(!m||req.method!=='POST'){envoyer(res,404,{message:'Inconnu'});return;}
 const fn=m[1];
 try{
  if(fn==='koki_public_feed'){envoyer(res,200,{version:1,contenus:[]});return;}
  const p=JSON.parse(corps||'{}');const vars={cmd:String(p.command||''),inp:JSON.stringify(p.input??{})};
  if(fn==='koki_foot_public'){
   envoyer(res,200,await psql(`select set_config('request.jwt.claims','{"role":"anon"}',false);\nset role anon;\nselect coalesce(public.koki_foot_public(:'cmd',:'inp'::jsonb)::text,'null');`,vars));return;}
  if(fn==='koki_foot_admin'){
   const role=req.headers['x-banc-role']||'editor',uid=UTILISATEURS[role];if(!uid){envoyer(res,401,{message:'Non connecté'});return;}
   vars.claims=JSON.stringify({sub:uid,aal:'aal2',role:'authenticated'});
   envoyer(res,200,await psql(`select set_config('request.jwt.claims',:'claims',false);\nset role authenticated;\nselect coalesce(public.koki_foot_admin(:'cmd',:'inp'::jsonb)::text,'null');`,vars));return;}
  envoyer(res,404,{message:'Fonction inconnue : '+fn});
 }catch(e){envoyer(res,400,{message:e.message});}
}).listen(PORT,'127.0.0.1',()=>console.log('banc Supabase simulé : http://127.0.0.1:'+PORT+' (base '+BASE+')'));
