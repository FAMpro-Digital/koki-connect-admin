// Ancrage externe du journal des corrections du module Football (PROPOSITION — non programmé, non déployé).
// Lit la dernière empreinte SHA-256 du journal (koki_foot_sync 'empreinte_journal', clé serveur), la SIGNE avec
// une clé Ed25519 qui n'est pas stockée chez Supabase, et produit un reçu JSON à conserver HORS de Supabase.
// Un recalcul complet de la chaîne dans la base ne correspondra plus aux reçus déjà archivés.
//
//   KOKI_SUPABASE_URL=… KOKI_SERVICE_KEY=… KOKI_ANCRAGE_CLE=cle-privee.pem node scripts/ancrage-journal.mjs lire > recu.json
//   node scripts/ancrage-journal.mjs verifier recu.json cle-publique.pem
//   node scripts/ancrage-journal.mjs comparer ancien.json nouveau.json   (le journal n'a fait que grandir ?)
import {createPrivateKey,createPublicKey,sign,verify,createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';

const canonique=o=>JSON.stringify(Object.keys(o).sort().reduce((a,k)=>(a[k]=o[k],a),{}));

export function signer(ancre,clePriveePem){
 for(const k of ['dernier_id','empreinte','lignes','lu_le'])if(!(k in ancre))throw Error('Ancre incomplète : '+k);
 if(ancre.premiere_alteration!==null)throw Error('Journal altéré à la ligne '+ancre.premiere_alteration+' : ancrage refusé, alerte à traiter');
 const cle=createPrivateKey(clePriveePem),pub=createPublicKey(cle).export({type:'spki',format:'der'});
 const donnees={dernier_id:ancre.dernier_id,empreinte:ancre.empreinte,lignes:ancre.lignes,lu_le:ancre.lu_le,module:'koki_foot.corrections'};
 return {...donnees,signature:sign(null,Buffer.from(canonique(donnees)),cle).toString('base64'),cle:createHash('sha256').update(pub).digest('hex').slice(0,16)};
}
export function verifier(recu,clePubliquePem){
 const {signature,cle:_,...donnees}=recu;
 return verify(null,Buffer.from(canonique(donnees)),createPublicKey(clePubliquePem),Buffer.from(signature,'base64'));
}
// Deux reçus successifs : le plus récent doit contenir au moins autant de lignes et un identifiant au moins égal.
// (La continuité exacte se contrôle en base avec verifier_journal ; un écart signale une réécriture.)
export function comparer(ancien,nouveau){
 if(nouveau.dernier_id<ancien.dernier_id||nouveau.lignes<ancien.lignes)return {ok:false,raison:'Le journal a rétréci depuis l’ancrage précédent'};
 if(nouveau.dernier_id===ancien.dernier_id&&nouveau.empreinte!==ancien.empreinte)return {ok:false,raison:'Même dernière ligne, empreinte différente : chaîne réécrite'};
 return {ok:true};
}
async function lire(){
 const url=process.env.KOKI_SUPABASE_URL,cle=process.env.KOKI_SERVICE_KEY;
 if(!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url||'')&&!/^http:\/\/127\.0\.0\.1:\d+$/.test(url||''))throw Error('KOKI_SUPABASE_URL invalide');
 if(!cle)throw Error('KOKI_SERVICE_KEY requise (variable d’environnement, jamais dans un fichier du dépôt)');
 const r=await fetch(url+'/rest/v1/rpc/koki_foot_sync',{method:'POST',headers:{apikey:cle,Authorization:'Bearer '+cle,'Content-Type':'application/json'},
  body:JSON.stringify({command:'empreinte_journal',input:{fournisseur:'api-football'}})});
 if(!r.ok)throw Error('Lecture impossible : HTTP '+r.status);
 return r.json();
}
if(import.meta.url===`file://${process.argv[1]}`){
 const [cmd,a,b]=process.argv.slice(2);
 try{
  if(cmd==='lire'){const pem=readFileSync(process.env.KOKI_ANCRAGE_CLE||'','utf8');console.log(JSON.stringify(signer(await lire(),pem),null,1));}
  else if(cmd==='verifier'){const ok=verifier(JSON.parse(readFileSync(a,'utf8')),readFileSync(b,'utf8'));console.log(ok?'Signature valide':'SIGNATURE INVALIDE');process.exit(ok?0:1);}
  else if(cmd==='comparer'){const r=comparer(JSON.parse(readFileSync(a,'utf8')),JSON.parse(readFileSync(b,'utf8')));console.log(r.ok?'Continuité plausible':'ALERTE : '+r.raison);process.exit(r.ok?0:1);}
  else{console.error('Usage : lire | verifier <reçu> <clé publique> | comparer <ancien> <nouveau>');process.exit(2);}
 }catch(e){console.error(e.message);process.exit(1);}
}
