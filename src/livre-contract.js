// Contrat commun « livre » de la Bibliothèque Éducation (à garder identique dans Koki Connect Admin).
// Stockage : public.koki_contents, type=Informations utiles, categorie=Éducation, texte = JSON versionné.
// Un livre payant ne publie JAMAIS de fichier : son fichier n'est remis qu'après achat (phase paiement).
(function(root){'use strict';
const marker='koki.education.book',version=1;
const categories=['Scolaire','Coran & religion','Alphabétisation','Formation pro','Jeunesse','Autre'];
const formats=['PDF','EPUB','Audio','Audio + PDF','Livre papier'];
const acces=['Gratuit','Payant'];
const fichierRe=/^[a-f0-9-]+\/[a-f0-9-]+\.(pdf|epub|mp3|m4a)$/;
const telRe=/^\+?[0-9 ()-]{6,24}$/;
const tailleMax=50; // Mo : limite d'envoi Supabase Free et taille raisonnable sur téléphone
function str(v,max){return typeof v==='string'&&v.length<=max;}
function check(v){
 if(!v||v.schema!==marker||v.version!==version)return false;
 if(!categories.includes(v.categorie)||!formats.includes(v.format)||!acces.includes(v.acces))return false;
 if(!['niveau','auteur','fournisseur','whatsapp','description','fichier'].every(k=>typeof v[k]==='string'))return false;
 if(!str(v.niveau,80)||!str(v.auteur,160)||!str(v.fournisseur,160)||!str(v.description,10000))return false;
 if(typeof v.archive!=='boolean'||!Number.isFinite(v.taille_mo)||v.taille_mo<0||v.taille_mo>tailleMax)return false;
 if(v.whatsapp&&!telRe.test(v.whatsapp))return false;
 if(v.acces==='Gratuit'){if(v.prix!==0)return false;}
 else if(!Number.isInteger(v.prix)||v.prix<=0||v.prix>10000000||v.fichier!=='')return false;
 if(v.fichier&&(!fichierRe.test(v.fichier)||v.format==='Livre papier'))return false;
 return true;
}
function decode(row){if(row?.type!=='Informations utiles'||row.categorie!=='Éducation')return null;try{const v=JSON.parse(row.texte);return check(v)?v:null;}catch{return null;}}
function encode(v){
 const s={schema:marker,version,categorie:v.categorie,niveau:String(v.niveau||'').trim(),format:v.format,acces:v.acces,
  prix:v.acces==='Gratuit'?0:Number(v.prix),auteur:String(v.auteur||'').trim(),fournisseur:String(v.fournisseur||'').trim(),
  whatsapp:String(v.whatsapp||'').trim(),description:String(v.description||'').trim(),
  fichier:v.acces==='Gratuit'?String(v.fichier||'').trim():'',taille_mo:Number(v.taille_mo)||0,archive:v.archive===true};
 if(!check(s)){
  if(s.acces==='Payant'&&!(Number.isInteger(s.prix)&&s.prix>0))throw Error('Indiquez un prix en FCFA pour un livre payant.');
  if(s.whatsapp&&!telRe.test(s.whatsapp))throw Error('Numéro WhatsApp invalide.');
  if(s.fichier&&!fichierRe.test(s.fichier))throw Error('Fichier invalide (PDF, EPUB, MP3 ou M4A téléversé dans koki-livres).');
  if(s.taille_mo>tailleMax)throw Error('Fichier trop lourd (50 Mo maximum).');
  throw Error('Fiche livre invalide.');
 }
 return JSON.stringify(s);
}
// Filtre Bibliothèque : accès (Tous/Gratuit/Payant), catégorie et recherche texte déjà normalisée.
function filtrer(items,{acces:a='Tous',categorie:c='Toutes',q=''}={},norm=x=>String(x).toLowerCase()){
 return items.filter(({row,livre})=>(a==='Tous'||livre.acces===a)&&(c==='Toutes'||livre.categorie===c)&&(!q||norm(row.titre+' '+row.resume+' '+livre.auteur+' '+livre.niveau+' '+livre.categorie).includes(q)));
}
function prix(n){return String(n).replace(/\B(?=(\d{3})+(?!\d))/g,' ')+' FCFA';}
function telechargeable(livre){return livre.acces==='Gratuit'&&!!livre.fichier&&livre.format!=='Livre papier';}
const api=Object.freeze({marker,version,categories,formats,acces,tailleMax,decode,encode,filtrer,prix,telechargeable});
root.KokiLivreContract=api;if(typeof module!=='undefined')module.exports=api;
})(globalThis);
