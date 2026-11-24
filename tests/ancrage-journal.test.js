// Ancrage externe du journal Football : signature Ed25519, vérification, détection d'une réécriture.
import test from 'node:test';import assert from 'node:assert/strict';import {generateKeyPairSync} from 'node:crypto';
import {signer,verifier,comparer} from '../scripts/ancrage-journal.mjs';
const {privateKey,publicKey}=generateKeyPairSync('ed25519');
const prive=privateKey.export({type:'pkcs8',format:'pem'}),pub=publicKey.export({type:'spki',format:'pem'});
const ancre={dernier_id:42,empreinte:'a'.repeat(64),lignes:42,premiere_alteration:null,lu_le:'2026-11-24T23:00:00Z'};

test('reçu signé et vérifiable avec la clé publique',()=>{
 const r=signer(ancre,prive);assert.equal(r.empreinte,ancre.empreinte);assert.ok(verifier(r,pub));
});
test('reçu modifié : signature invalide',()=>{
 const r=signer(ancre,prive);assert.equal(verifier({...r,empreinte:'b'.repeat(64)},pub),false);assert.equal(verifier({...r,lignes:41},pub),false);
});
test('autre clé : signature invalide',()=>{
 const autre=generateKeyPairSync('ed25519').publicKey.export({type:'spki',format:'pem'});assert.equal(verifier(signer(ancre,prive),autre),false);
});
test('journal altéré : ancrage refusé',()=>{assert.throws(()=>signer({...ancre,premiere_alteration:7},prive),/altéré à la ligne 7/);});
test('comparaison de deux reçus : croissance normale, rétrécissement ou réécriture détectés',()=>{
 assert.equal(comparer(ancre,{...ancre,dernier_id:50,lignes:50,empreinte:'c'.repeat(64)}).ok,true);
 assert.match(comparer(ancre,{...ancre,dernier_id:40,lignes:40}).raison,/rétréci/);
 assert.match(comparer(ancre,{...ancre,empreinte:'d'.repeat(64)}).raison,/réécrite/);
});

// ── Rotation des clés, série de reçus, troncature, absence de secrets ──
import {verifierSuite,sansSecret,empreinteCle,empreinteRecu} from '../scripts/ancrage-journal.mjs';
const k2=generateKeyPairSync('ed25519');const prive2=k2.privateKey.export({type:'pkcs8',format:'pem'}),pub2=k2.publicKey.export({type:'spki',format:'pem'});
const h=n=>String(n).repeat(64).slice(0,64);
// Série : 3 reçus avec la clé 1, rotation le 3 décembre, 2 reçus avec la clé 2.
function serie(){
 const r=[];let prec=null;
 const pas=[[10,'1','2026-12-01T23:00:00Z',prive],[20,'2','2026-12-02T23:00:00Z',prive],[20,'2','2026-12-02T23:30:00Z',prive],[35,'3','2026-12-03T23:00:00Z',prive2],[40,'4','2026-12-04T23:00:00Z',prive2]];
 const lignes={};
 for(const [id,e,lu,cle] of pas){lignes[id]=h(e);
  const a={dernier_id:id,empreinte:h(e),lignes:id,premiere_alteration:null,lu_le:lu,controle:prec?{id:prec.dernier_id,empreinte:lignes[prec.dernier_id]}:undefined};
  prec=signer(a,cle,prec);r.push(prec);}
 return r;
}
const trousseau={cles:[{id:empreinteCle(pub),publique:pub,valide_du:'2026-12-01T00:00:00Z',valide_au:'2026-12-03T00:00:00Z'},{id:empreinteCle(pub2),publique:pub2,valide_du:'2026-12-03T00:00:00Z',valide_au:null}]};

test('série de reçus avec rotation de clé : valide',()=>{const r=verifierSuite(trousseau,serie());assert.deepEqual(r.erreurs,[]);assert.ok(r.ok);});
test('rotation : reçu signé avec la clé retirée après sa date de retrait refusé',()=>{
 const s=serie();const faux=signer({dernier_id:50,empreinte:h(5),lignes:50,premiere_alteration:null,lu_le:'2026-12-05T23:00:00Z',controle:{id:40,empreinte:s[4].empreinte}},prive,s[4]);
 assert.match(verifierSuite(trousseau,[...s,faux]).erreurs.join(),/clé retirée/);
});
test('rotation : clé inconnue du trousseau, ou trousseau falsifié, refusés',()=>{
 const s=serie();assert.match(verifierSuite({cles:[trousseau.cles[0]]},s).erreurs.join(),/Clé inconnue/);
 const t2={cles:[{...trousseau.cles[0],publique:pub2},trousseau.cles[1]]};assert.match(verifierSuite(t2,s).erreurs.join(),/incohérent/);
});
test('chaîne des reçus : reçu supprimé, remplacé ou réordonné détecté',()=>{
 const s=serie();
 assert.match(verifierSuite(trousseau,[s[0],s[2],s[3],s[4]]).erreurs.join(),/chaîne des reçus rompue/);
 assert.match(verifierSuite(trousseau,[s[1],s[0],s[2],s[3],s[4]]).erreurs.join(),/rompue|date non croissante/);
 const modifie={...s[2],lignes:21};assert.match(verifierSuite(trousseau,[s[0],s[1],modifie]).erreurs.join(),/signature invalide/);
});
test('journal tronqué : ligne de contrôle disparue => ancrage refusé',()=>{
 const s=serie();
 assert.throws(()=>signer({dernier_id:45,empreinte:h(9),lignes:45,premiere_alteration:null,lu_le:'2026-12-05T23:00:00Z',controle:{id:40,empreinte:null}},prive2,s[4]),/TRONQUÉ/);
 assert.throws(()=>signer({dernier_id:30,empreinte:h(9),lignes:30,premiere_alteration:null,lu_le:'2026-12-05T23:00:00Z',controle:{id:40,empreinte:s[4].empreinte}},prive2,s[4]),/TRONQUÉ/);
});
test('chaîne réécrite puis recalculée en base : détectée par le contrôle',()=>{
 const s=serie();
 assert.throws(()=>signer({dernier_id:45,empreinte:h(9),lignes:45,premiere_alteration:null,lu_le:'2026-12-05T23:00:00Z',controle:{id:40,empreinte:h(7)}},prive2,s[4]),/RÉÉCRITE/);
 assert.throws(()=>signer({dernier_id:45,empreinte:h(9),lignes:45,premiere_alteration:null,lu_le:'2026-12-05T23:00:00Z'},prive2,s[4]),/Contrôle de continuité absent/);
});
test('reçus : aucun secret (clé privée, jeton, clé serveur) et champs connus seulement',()=>{
 for(const r of serie()){assert.ok(sansSecret(r).ok);const t=JSON.stringify(r);assert.doesNotMatch(t,/PRIVATE|BEGIN|eyJ/);}
 assert.equal(sansSecret({...serie()[0],apikey:'x'}).ok,false);
 assert.equal(sansSecret({...serie()[0],lu_le:'eyJhbGciOiJIUzI1NiIsInR5cCI6.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x'}).ok,false);
 assert.equal(empreinteRecu(serie()[0]).length,64);
});
