// Génère une paire de clés Ed25519 pour l'ancrage du journal Football — À LANCER HORS LIGNE, sur un poste de confiance.
// Usage : node generer-cle.mjs <fichier-clé-privée-hors-dépôt> [valide_du ISO]
// Écrit la clé privée (droits 600) au chemin indiqué et affiche l'entrée publique à ajouter au trousseau.
// La clé privée ne doit jamais être déposée dans un dépôt ni chez Supabase : seul le secret KOKI_ANCRAGE_CLE_PEM
// du dépôt d'ancrage la contient.
import {generateKeyPairSync,createHash} from 'node:crypto';import {writeFileSync,existsSync} from 'node:fs';import path from 'node:path';
const [chemin,du=new Date().toISOString()]=process.argv.slice(2);
if(!chemin)throw Error('Chemin de la clé privée requis');
if(existsSync(chemin))throw Error('Refus : le fichier existe déjà');
if(existsSync(path.join(path.dirname(path.resolve(chemin)),'.git')))throw Error('Refus : dossier d’un dépôt Git');
const k=generateKeyPairSync('ed25519');
writeFileSync(chemin,k.privateKey.export({type:'pkcs8',format:'pem'}),{mode:0o600});
const publique=k.publicKey.export({type:'spki',format:'pem'});
const id=createHash('sha256').update(k.publicKey.export({type:'spki',format:'der'})).digest('hex').slice(0,16);
console.log(JSON.stringify({id,publique,valide_du:du,valide_au:null},null,1));
