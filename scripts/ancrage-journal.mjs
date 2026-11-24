// Ancrage externe du journal des corrections du module Football (PROPOSITION — non programmé, non déployé).
// Lit la dernière empreinte SHA-256 du journal (koki_foot_sync 'empreinte_journal', clé serveur), la SIGNE avec
// une clé Ed25519 qui n'est pas stockée chez Supabase, et produit un reçu JSON à conserver HORS de Supabase.
// Chaque reçu porte : l'empreinte de la dernière ligne, l'empreinte ACTUELLE de la dernière ligne du reçu
// précédent (« controle » : prouve que la chaîne n'a été ni tronquée ni réécrite), l'empreinte du reçu
// précédent (« precedent » : chaîne des reçus) et l'identifiant de la clé (rotation par trousseau).
//
//   KOKI_SUPABASE_URL=… KOKI_SERVICE_KEY=… KOKI_ANCRAGE_CLE=cle-privee.pem node scripts/ancrage-journal.mjs lire [precedent.json] > recu.json
//   node scripts/ancrage-journal.mjs verifier recu.json cle-publique.pem
//   node scripts/ancrage-journal.mjs comparer ancien.json nouveau.json
//   node scripts/ancrage-journal.mjs suite trousseau.json recu1.json recu2.json …   (vérification complète d'une série)
import {createPrivateKey,createPublicKey,sign,verify,createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';

const canonique=o=>JSON.stringify(Object.keys(o).sort().reduce((a,k)=>(a[k]=o[k],a),{}));

const CHAMPS=['cle','controle','dernier_id','empreinte','lignes','lu_le','module','precedent','signature','version'];
export const empreinteCle=pem=>createHash('sha256').update((typeof pem==='object'&&pem.type==='public'?pem:createPublicKey(pem)).export({type:'spki',format:'der'})).digest('hex').slice(0,16);
export const empreinteRecu=recu=>createHash('sha256').update(canonique(recu)).digest('hex');

// precedent : reçu précédent (ou null pour le premier). L'ancre doit alors contenir controle = {id, empreinte}
// lu en base pour precedent.dernier_id.
export function signer(ancre,clePriveePem,precedent=null){
 for(const k of ['dernier_id','empreinte','lignes','lu_le'])if(!(k in ancre))throw Error('Ancre incomplète : '+k);
 if(ancre.premiere_alteration!==null)throw Error('Journal altéré à la ligne '+ancre.premiere_alteration+' : ancrage refusé, alerte à traiter');
 let controle=null;
 if(precedent){
  if(!ancre.controle||ancre.controle.id!==precedent.dernier_id)throw Error('Contrôle de continuité absent : relire avec controle_id='+precedent.dernier_id);
  if(ancre.controle.empreinte!==precedent.empreinte)throw Error(ancre.controle.empreinte===null?'Journal TRONQUÉ : la ligne '+precedent.dernier_id+' a disparu':'Chaîne RÉÉCRITE : la ligne '+precedent.dernier_id+' a changé d’empreinte');
  const c=comparer(precedent,ancre);if(!c.ok)throw Error(c.raison);
  controle=ancre.controle;
 }
 const cle=createPrivateKey(clePriveePem);
 const donnees={version:2,module:'koki_foot.corrections',dernier_id:ancre.dernier_id,empreinte:ancre.empreinte,lignes:ancre.lignes,lu_le:ancre.lu_le,
  controle,precedent:precedent?empreinteRecu(precedent):null,cle:empreinteCle(createPublicKey(cle))};
 return {...donnees,signature:sign(null,Buffer.from(canonique(donnees)),cle).toString('base64')};
}
export function verifier(recu,clePubliquePem){
 const {signature,...donnees}=recu;
 // Reçus version 1 (sans identifiant de clé signé) : l'identifiant n'entre pas dans la signature.
 if(!recu.version)delete donnees.cle;
 try{return verify(null,Buffer.from(canonique(donnees)),createPublicKey(clePubliquePem),Buffer.from(signature,'base64'));}catch{return false;}
}
// Deux reçus successifs : le plus récent doit contenir au moins autant de lignes et un identifiant au moins égal.
export function comparer(ancien,nouveau){
 if(nouveau.dernier_id<ancien.dernier_id||nouveau.lignes<ancien.lignes)return {ok:false,raison:'Journal TRONQUÉ : il a rétréci depuis l’ancrage précédent'};
 if(nouveau.dernier_id===ancien.dernier_id&&nouveau.empreinte!==ancien.empreinte)return {ok:false,raison:'Même dernière ligne, empreinte différente : chaîne réécrite'};
 if(nouveau.dernier_id===ancien.dernier_id&&nouveau.lignes!==ancien.lignes)return {ok:false,raison:'Même dernière ligne, nombre de lignes différent'};
 if(nouveau.controle&&nouveau.controle.id===ancien.dernier_id&&nouveau.controle.empreinte!==ancien.empreinte)return {ok:false,raison:'Continuité rompue à la ligne '+ancien.dernier_id};
 return {ok:true};
}
// Un reçu ne doit contenir que des champs publics : aucun secret, aucune clé privée, aucun jeton.
export function sansSecret(recu){
 const inconnus=Object.keys(recu).filter(k=>!CHAMPS.includes(k));if(inconnus.length)return {ok:false,raison:'Champs inattendus : '+inconnus.join(', ')};
 const t=JSON.stringify(recu);
 if(/PRIVATE KEY|BEGIN |eyJ[A-Za-z0-9_-]{15,}\.|service_role|sb_secret_|apikey/i.test(t))return {ok:false,raison:'Secret présent dans le reçu'};
 return {ok:true};
}
// Trousseau : {"cles":[{"id":"<empreinte>","publique":"-----BEGIN PUBLIC KEY-----…","valide_du":"…","valide_au":null|"…"}]}
// Rotation : la nouvelle clé est ajoutée, l'ancienne reçoit une date valide_au ; elle reste pour vérifier l'historique.
export function cleDuTrousseau(trousseau,recu){
 const k=(trousseau.cles||[]).find(x=>x.id===recu.cle);
 if(!k)return {ok:false,raison:'Clé inconnue du trousseau : '+recu.cle};
 if(empreinteCle(k.publique)!==k.id)return {ok:false,raison:'Trousseau incohérent : empreinte de la clé '+k.id};
 const t=Date.parse(recu.lu_le);
 if(k.valide_du&&t<Date.parse(k.valide_du))return {ok:false,raison:'Reçu antérieur à la mise en service de la clé '+k.id};
 if(k.valide_au&&t>Date.parse(k.valide_au))return {ok:false,raison:'Reçu signé avec la clé retirée '+k.id};
 return {ok:true,publique:k.publique};
}
// Série complète de reçus (ordre chronologique) : signature, clé valide à la date, absence de secret,
// chaîne des reçus (precedent), continuité du journal (controle), croissance.
export function verifierSuite(trousseau,recus){
 const erreurs=[];
 recus.forEach((r,i)=>{
  const n='reçu '+(i+1)+' (ligne '+r.dernier_id+')';
  const s=sansSecret(r);if(!s.ok)erreurs.push(n+' : '+s.raison);
  const k=cleDuTrousseau(trousseau,r);if(!k.ok)erreurs.push(n+' : '+k.raison);else if(!verifier(r,k.publique))erreurs.push(n+' : signature invalide');
  if(i===0)return;
  const a=recus[i-1];
  if(r.precedent!==empreinteRecu(a))erreurs.push(n+' : chaîne des reçus rompue (reçu manquant, remplacé ou réordonné)');
  if(!r.controle||r.controle.id!==a.dernier_id)erreurs.push(n+' : contrôle de continuité absent');
  const c=comparer(a,r);if(!c.ok)erreurs.push(n+' : '+c.raison);
  if(Date.parse(r.lu_le)<=Date.parse(a.lu_le))erreurs.push(n+' : date non croissante');
 });
 return {ok:erreurs.length===0,erreurs};
}
async function lire(controleId=null){
 const url=process.env.KOKI_SUPABASE_URL,cle=process.env.KOKI_SERVICE_KEY;
 if(!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url||'')&&!/^http:\/\/127\.0\.0\.1:\d+$/.test(url||''))throw Error('KOKI_SUPABASE_URL invalide');
 if(!cle)throw Error('KOKI_SERVICE_KEY requise (variable d’environnement, jamais dans un fichier du dépôt)');
 const r=await fetch(url+'/rest/v1/rpc/koki_foot_sync',{method:'POST',headers:{apikey:cle,Authorization:'Bearer '+cle,'Content-Type':'application/json'},
  body:JSON.stringify({command:'empreinte_journal',input:{fournisseur:'api-football',...(controleId!==null?{controle_id:controleId}:{})}})});
 if(!r.ok)throw Error('Lecture impossible : HTTP '+r.status);
 return r.json();
}
if(import.meta.url===`file://${process.argv[1]}`){
 const [cmd,a,b,...reste]=process.argv.slice(2);
 try{
  if(cmd==='lire'){const pem=readFileSync(process.env.KOKI_ANCRAGE_CLE||'','utf8');const prec=a?JSON.parse(readFileSync(a,'utf8')):null;
   console.log(JSON.stringify(signer(await lire(prec?prec.dernier_id:null),pem,prec),null,1));}
  else if(cmd==='suite'){const r=verifierSuite(JSON.parse(readFileSync(a,'utf8')),[b,...reste].map(f=>JSON.parse(readFileSync(f,'utf8'))));
   console.log(r.ok?'Série valide : '+(reste.length+1)+' reçus':'ALERTE :\n'+r.erreurs.join('\n'));process.exit(r.ok?0:1);}
  else if(cmd==='verifier'){const ok=verifier(JSON.parse(readFileSync(a,'utf8')),readFileSync(b,'utf8'));console.log(ok?'Signature valide':'SIGNATURE INVALIDE');process.exit(ok?0:1);}
  else if(cmd==='comparer'){const r=comparer(JSON.parse(readFileSync(a,'utf8')),JSON.parse(readFileSync(b,'utf8')));console.log(r.ok?'Continuité plausible':'ALERTE : '+r.raison);process.exit(r.ok?0:1);}
  else{console.error('Usage : lire [reçu précédent] | verifier <reçu> <clé publique> | comparer <ancien> <nouveau> | suite <trousseau> <reçus…>');process.exit(2);}
 }catch(e){console.error(e.message);process.exit(1);}
}
