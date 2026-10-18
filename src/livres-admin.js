// Éducation · Bibliothèque (livres) et Vue d'ensemble de la rubrique Éducation.
// Mêmes enregistrements que l'application publique : koki_contents, contrat koki.education.book.
import './livre-contract.js';
import './education-contract.js';
import {bindImageProcessing} from './image-processing.js';
import {saveImageRecord} from './images.js';
import {formatContrat} from './livre-fichier.js';
const L=globalThis.KokiLivreContract,S=globalThis.KokiEducationContract;
// La fenêtre est ouverte tout de suite (sinon Safari la bloque), puis reçoit le lien temporaire.
async function ouvrirFichier(guard,bookURL,path){const w=window.open('about:blank','_blank');try{await guard();const url=await bookURL(path);if(w)w.location.href=url;else location.href=url;}catch(e){if(w)w.close();throw e;}}

// État lisible d'une fiche (archivé, programmé, publié, brouillon).
export function etat(row,archive,now=Date.now()){if(archive)return 'Archivé';if(row.statut==='publié')return Date.parse(row.publication)>now?'Programmé':'Publié';return 'Brouillon';}
// Points à corriger avant (ou après) publication : c'est ce qui permet de mieux contrôler la rubrique.
export function problemesLivre(row,livre){
 const p=[];if(livre.archive)return p;
 const numerique=livre.format!=='Livre papier';
 if(livre.acces==='Gratuit'&&numerique&&!livre.fichier)p.push('Livre gratuit sans fichier : personne ne peut le lire.');
 if(livre.acces==='Payant'&&!livre.whatsapp)p.push('Livre payant sans numéro WhatsApp : impossible à commander.');
 if(livre.format==='Livre papier'&&!livre.whatsapp&&!livre.fournisseur)p.push('Livre papier sans fournisseur ni WhatsApp.');
 if(!row.image_path)p.push('Pas de couverture (photo).');
 if(!livre.niveau)p.push('Niveau non renseigné.');
 return p;
}
export function problemesEcole(row,ecole){const p=[];if(ecole.archive)return p;if(!ecole.telephone)p.push('Pas de téléphone.');if(!ecole.horaires)p.push('Horaires non renseignés.');if(!row.image_path)p.push('Pas de photo.');return p;}
// Compteurs de la vue d'ensemble, calculés sur les vraies fiches.
export function bilanEducation(rows,now=Date.now()){
 const b={ecoles:{total:0,Publié:0,Programmé:0,Brouillon:0,Archivé:0,aVerifier:0},livres:{total:0,Publié:0,Programmé:0,Brouillon:0,Archivé:0,gratuits:0,payants:0,telechargeables:0,aVerifier:0},alertes:[]};
 for(const row of rows){const e=S.decode(row),l=L.decode(row);
  if(e){const s=etat(row,e.archive,now);b.ecoles.total++;b.ecoles[s]++;const p=problemesEcole(row,e);if(p.length){b.ecoles.aVerifier++;b.alertes.push({row,genre:'ecole',problemes:p});}}
  else if(l){const s=etat(row,l.archive,now);b.livres.total++;b.livres[s]++;if(!l.archive){if(l.acces==='Gratuit')b.livres.gratuits++;else b.livres.payants++;if(L.telechargeable(l))b.livres.telechargeables++;}const p=problemesLivre(row,l);if(p.length){b.livres.aVerifier++;b.alertes.push({row,genre:'livre',problemes:p});}}}
 return b;
}
async function chargerEducation(db,result){const rows=[];for(let offset=0;;offset+=200){const page=await result(db.from('koki_contents').select('*').eq('type','Informations utiles').eq('categorie','Éducation').order('id').range(offset,offset+199));rows.push(...page);if(page.length<200)break;}return rows;}

export async function renderLivres(main,ctx){
 const {n,button,field,formPanel,configured,db,result,guard,can,account,write,media,imageURL,imagePreview,error,refresh,bookUpload,bookURL,bookRemove}=ctx;
 const editable=configured&&can(account?.role,'content');
 main.append(n('p','Bibliothèque · Livres gratuits (téléchargeables) et payants (commande WhatsApp), partagés avec Koki Connect. Fichiers PDF, EPUB, MP3 ou M4A, 50 Mo maximum.'));

 async function edit(row){
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  const old=L.decode(row)||{};ctx.startEditor(row?'Modifier un livre':'Ajouter un livre');const f=formPanel(),m={};
  field(f,m,'titre','Titre du livre','text',null,row?.titre||'',true);
  field(f,m,'resume','Présentation courte (visible dans la liste)','textarea',null,row?.resume||'',true);
  field(f,m,'categorie','Catégorie','text',L.categories,old.categorie||L.categories[0],true);
  field(f,m,'niveau','Niveau / public (ex. CM2, 3e, Adultes)','text',null,old.niveau||'');
  field(f,m,'format','Format','text',L.formats,old.format||'PDF',true);
  field(f,m,'acces','Accès','text',L.acces,old.acces||'Gratuit',true);
  const prix=field(f,m,'prix','Prix en FCFA (livre payant)','number',null,old.acces==='Payant'?old.prix:'');prix.step='1';prix.min='1';
  field(f,m,'auteur','Auteur','text',null,old.auteur||'');
  field(f,m,'fournisseur','Fourni par (librairie, centre, auteur…)','text',null,old.fournisseur||'');
  field(f,m,'whatsapp','WhatsApp pour commander','tel',null,old.whatsapp||'');
  field(f,m,'description','Description complète','textarea',null,old.description||'');
  const fichier=field(f,m,'fichier','Fichier du livre gratuit : PDF, EPUB, MP3 ou M4A (50 Mo maximum)','file');fichier.accept='.pdf,.epub,.mp3,.m4a,application/pdf,application/epub+zip,audio/mpeg,audio/mp4';
  const infoFichier=n('p',old.fichier?'Fichier actuel : '+old.taille_mo+' Mo':'Aucun fichier enregistré.');f.append(infoFichier);
  let retirer=null;if(old.fichier){const l=n('label','Retirer le fichier actuel');retirer=n('input');retirer.type='checkbox';l.prepend(retirer);f.append(l,button('Ouvrir le fichier actuel',()=>ouvrirFichier(guard,bookURL,old.fichier)));}
  field(f,m,'source','Source / responsable de publication','text',null,row?.source||'');
  field(f,m,'statut','Visibilité','text',['brouillon','publié'],row?.statut||'brouillon',true);
  field(f,m,'publication','Date de publication (heure de Koki)','datetime-local',null,(row?.publication||new Date().toISOString()).slice(0,16),true);
  field(f,m,'photo','Couverture (photo, 10 Mo maximum, compression automatique)','file');
  const regle=n('p');regle.className='hint';f.append(regle);
  function maj(){const payant=m.acces.value==='Payant',papier=m.format.value==='Livre papier';prix.closest('label').hidden=!payant;prix.required=payant;fichier.closest('label').hidden=payant||papier;fichier.disabled=payant||papier;
   regle.textContent=payant?'Livre payant : aucun fichier n’est publié. Les lecteurs commandent sur WhatsApp ; le paiement en ligne viendra dans une phase suivante.':papier?'Livre papier : indiquez où l’obtenir (fournisseur, WhatsApp).':'Livre gratuit : le fichier sera téléchargeable et lisible sans internet dans l’application.';}
  m.acces.onchange=maj;m.format.onchange=maj;maj();
  const preview=n('section');f.append(preview);const previewFile=imagePreview(preview,row?.image_path,imageURL);
  const submit=n('button','Enregistrer le livre');submit.type='submit';submit.className='primary';const selected=bindImageProcessing(m.photo,preview,previewFile,submit);f.append(submit,button('Annuler',refresh));
  f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;let envoye=null;try{
   await guard();const v=Object.fromEntries(['titre','resume','categorie','niveau','format','acces','prix','auteur','fournisseur','whatsapp','description','source','statut','publication'].map(k=>[k,m[k].value.trim()]));
   if(!v.titre||!v.resume)throw Error('Titre et présentation requis.');
   const gratuitNumerique=v.acces==='Gratuit'&&v.format!=='Livre papier';
   let chemin=gratuitNumerique&&!(retirer&&retirer.checked)?old.fichier||'':'',taille=chemin?old.taille_mo:0,format=v.format;
   const nouveau=gratuitNumerique?fichier.files[0]:null;
   if(nouveau){envoye=await bookUpload(nouveau);chemin=envoye.path;taille=envoye.taille_mo;format=formatContrat(envoye.type,v.format);}
   const texte=L.encode({categorie:v.categorie,niveau:v.niveau,format,acces:v.acces,prix:v.acces==='Payant'?Number(v.prix):0,auteur:v.auteur,fournisseur:v.fournisseur,whatsapp:v.whatsapp,description:v.description,fichier:chemin,taille_mo:taille,archive:false});
   const data={type:'Informations utiles',categorie:'Éducation',titre:v.titre,resume:v.resume,lieu:row?.lieu||'',source:v.source,statut:v.statut,publication:new Date(v.publication+'Z').toISOString(),texte,image_path:row?.image_path||null};
   await saveImageRecord({data,file:selected(),content:true,upload:media,persist:value=>write('koki_contents',value,row),cleanup:path=>result(db.storage.from('koki-media').remove([path]))});
   envoye=null;
   if(old.fichier&&old.fichier!==chemin){try{await bookRemove(old.fichier);}catch{/* l’ancien fichier reste privé et non référencé */}}
   await refresh();
  }catch(err){if(envoye){try{await bookRemove(envoye.path);}catch{/* conserver l’erreur d’origine */}}error(err);}finally{submit.disabled=false;}};
  main.append(f);
 }

 const add=button('Ajouter un livre',()=>edit(),'primary');add.disabled=!editable;main.append(add,button('Actualiser',refresh));
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 const rows=(await chargerEducation(db,result)).filter(r=>L.decode(r));if(!main.isConnected)return;
 const b=bilanEducation(rows).livres;
 main.append(n('p',b.total+' livre(s) · '+b.Publié+' publié(s) · '+b.Brouillon+' brouillon(s) · '+b.Archivé+' archivé(s) · '+b.gratuits+' gratuit(s) dont '+b.telechargeables+' téléchargeable(s) · '+b.payants+' payant(s) · '+b.aVerifier+' à vérifier'));
 const search=n('input');search.type='search';search.placeholder='Rechercher un titre, un auteur, un niveau…';search.setAttribute('aria-label','Rechercher un livre');
 const filtre=n('select');filtre.setAttribute('aria-label','Filtrer les livres');for(const x of ['Tous','Gratuits','Payants','Publiés','Programmés','Brouillons','Archivés','À vérifier']){const o=n('option',x);o.value=x;filtre.append(o);}
 const grid=n('div');grid.className='list';main.append(search,filtre,grid);
 function garde(row,livre){const s=etat(row,livre.archive);switch(filtre.value){case 'Gratuits':return livre.acces==='Gratuit'&&!livre.archive;case 'Payants':return livre.acces==='Payant'&&!livre.archive;case 'Publiés':return s==='Publié';case 'Programmés':return s==='Programmé';case 'Brouillons':return s==='Brouillon';case 'Archivés':return s==='Archivé';case 'À vérifier':return problemesLivre(row,livre).length>0;default:return true;}}
 function show(){grid.replaceChildren();const q=search.value.toLocaleLowerCase('fr');
  const found=rows.filter(r=>{const l=L.decode(r);return garde(r,l)&&(r.titre+' '+l.auteur+' '+l.niveau+' '+l.categorie+' '+l.fournisseur).toLocaleLowerCase('fr').includes(q);});
  for(const row of found){const livre=L.decode(row),card=n('article');card.className='card';
   card.append(n('h2',row.titre),n('p',etat(row,livre.archive)+' · '+(livre.acces==='Gratuit'?'Gratuit':L.prix(livre.prix))+' · '+livre.categorie+(livre.niveau?' · '+livre.niveau:'')+' · '+livre.format),
    n('p',livre.fichier?'Fichier : '+livre.taille_mo+' Mo':livre.acces==='Payant'?'Commande WhatsApp '+(livre.whatsapp||'(numéro manquant)'):'Sans fichier'),n('p',row.resume));
   const p=problemesLivre(row,livre);if(p.length){const ul=n('ul');ul.className='hint';for(const x of p)ul.append(n('li','⚠ '+x));card.append(ul);}
   if(row.image_path)imagePreview(card,row.image_path,imageURL);
   const modify=button('Modifier',()=>edit(row));modify.disabled=!editable;card.append(modify);
   if(livre.fichier)card.append(button('Ouvrir le fichier',()=>ouvrirFichier(guard,bookURL,livre.fichier)));
   if(!livre.archive){
    const bascule=button(row.statut==='publié'?'Dépublier':'Publier maintenant',async()=>{await guard();if(row.statut!=='publié'&&!confirm('Publier « '+row.titre+' » dans l’application maintenant ?'))return;await write('koki_contents',row.statut==='publié'?{statut:'brouillon'}:{statut:'publié',publication:new Date().toISOString()},row);await refresh();});bascule.disabled=!editable;
    const archive=button('Archiver',async()=>{if(!confirm('Archiver ce livre et le retirer de la bibliothèque publique ?'))return;await guard();await write('koki_contents',{statut:'brouillon',texte:L.encode({...livre,archive:true})},row);await refresh();});archive.disabled=!editable;card.append(bascule,archive);
   }else{const restaurer=button('Restaurer en brouillon',async()=>{await guard();await write('koki_contents',{statut:'brouillon',texte:L.encode({...livre,archive:false})},row);await refresh();});restaurer.disabled=!editable;card.append(restaurer);}
   grid.append(card);}
  if(!found.length)grid.append(n('p','Aucun livre pour ce filtre.'));}
 search.oninput=show;filtre.onchange=show;show();
 if(ctx.open){const cible=rows.find(r=>r.id===ctx.open);if(cible&&editable)await edit(cible);}
}

export async function renderEducationApercu(main,ctx){
 const {n,button,configured,db,result,can,account,navigate}=ctx;
 main.append(n('p','Rubrique Éducation de l’application : établissements scolaires et bibliothèque. Tout ce qui est publié ici apparaît dans Koki Connect.'));
 const actions=n('div');actions.className='quick-actions';const editable=configured&&can(account?.role,'content');
 for(const [label,cible]of [['🏫 Gérer les établissements','education'],['📚 Gérer la bibliothèque','livres']])actions.append(button(label,()=>navigate(cible),'primary'));
 main.append(actions);
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 const rows=await chargerEducation(db,result);if(!main.isConnected)return;const b=bilanEducation(rows);
 const grid=n('div');grid.className='grid dashboard-metrics';
 for(const [titre,v,note,cible]of [['Établissements publiés',b.ecoles.Publié,b.ecoles.Brouillon+' brouillon(s) · '+b.ecoles.Programmé+' programmé(s) · '+b.ecoles.Archivé+' archivé(s)','education'],
  ['Livres publiés',b.livres.Publié,b.livres.Brouillon+' brouillon(s) · '+b.livres.Programmé+' programmé(s) · '+b.livres.Archivé+' archivé(s)','livres'],
  ['Livres gratuits',b.livres.gratuits,b.livres.telechargeables+' téléchargeable(s) hors ligne','livres'],['Livres payants',b.livres.payants,'Commande WhatsApp','livres'],
  ['À vérifier',b.ecoles.aVerifier+b.livres.aVerifier,b.ecoles.aVerifier+' établissement(s) · '+b.livres.aVerifier+' livre(s)',null]]){
  const c=n('article');c.className='card metric';const t=n('div');t.append(n('p',titre),n('strong',String(v)),n('small',note));c.append(t);if(cible)c.append(button('Ouvrir',()=>navigate(cible)));grid.append(c);}
 main.append(grid);
 const panel=n('section');panel.className='panel review-panel';panel.append(n('h2','À vérifier'));
 for(const a of b.alertes.slice(0,50)){const row=n('article');row.className='dashboard-row';row.append(n('strong',(a.genre==='livre'?'📚 ':'🏫 ')+a.row.titre),n('small',etat(a.row,false)),n('p',a.problemes.join(' ')));const ouvrir=button('Corriger',()=>navigate(a.genre==='livre'?'livres':'education','',a.row.id));ouvrir.disabled=!editable;row.append(ouvrir);panel.append(row);}
 if(!b.alertes.length)panel.append(n('p','Rien à signaler : toutes les fiches actives sont complètes.'));
 if(b.alertes.length>50)panel.append(n('p','Seules les 50 premières alertes sont affichées.'));
 main.append(panel);
}
