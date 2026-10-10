// Écran « Numéros utiles » : contenus koki_contents (type Informations utiles, catégorie Numéros utiles)
// au format du contrat partagé numeros-contract.js (identique dans l'application publique).
import './numeros-contract.js';
const K=globalThis.KokiNumeroContract;

// Numéros d'urgence nationaux vérifiés le 2026-10-10 (source publique citée), importés en brouillons.
const SOURCE_URGENCES='Senego.com, liste « Numéros d’urgence au Sénégal » (consultée le 2026-10-10)';
export const urgencesNationales=[
 {titre:'Police secours',telephone:'17',description:'Appel gratuit, urgences de police.'},
 {titre:'Sapeurs-pompiers',telephone:'18',description:'Incendies, accidents, secours.'},
 {titre:'SAMU national',telephone:'1515',description:'Urgences médicales.'},
 {titre:'Numéro vert violences basées sur le genre',telephone:'800 00 20 20',description:'Gratuit et confidentiel.'}
].map(x=>({...x,groupe:'Urgences nationales',source:SOURCE_URGENCES,verifie_le:'2026-10-10'}));

export const chiffres=telephone=>String(telephone??'').replace(/\D/g,'');

// Prépare la ligne koki_contents. La date de publication est saisie à l'heure de Koki (UTC).
export function construireLigne(v){
 const titre=String(v.titre??'').trim(),source=String(v.source??'').trim(),statut=v.statut||'brouillon';
 if(titre.length<2||titre.length>180)throw Error('Nom du service obligatoire (2 à 180 caractères).');
 if(source.length<3||source.length>300)throw Error('Source obligatoire : indiquez d’où vient le numéro (appel, affiche officielle, site…).');
 if(!['brouillon','publié'].includes(statut))throw Error('Visibilité invalide.');
 const publication=v.publication?new Date(String(v.publication).length===16?v.publication+':00Z':v.publication):new Date();
 if(!Number.isFinite(publication.getTime()))throw Error('Date de publication invalide.');
 const texte=K.encode({groupe:v.groupe,telephone:v.telephone,description:v.description,verifie_le:v.verifie_le,archive:false});
 const description=String(v.description??'').trim();
 return {type:K.type,categorie:K.categorie,titre,resume:description||v.groupe,lieu:'',source,statut,publication:publication.toISOString(),texte,image_path:null};
}

// Autres numéros actifs (non archivés) portant les mêmes chiffres.
export function doublons(rows,telephone,exceptId){const c=chiffres(telephone);return rows.filter(r=>r.id!==exceptId&&(K.decode(r)?.archive===false)&&chiffres(K.decode(r).telephone)===c);}

export function etat(row,now=Date.now()){const v=K.decode(row);if(!v)return 'Invalide';if(v.archive)return 'Archivé';if(row.statut==='publié')return Date.parse(row.publication)>now?'Programmé':'Publié';return 'Brouillon';}

export async function renderNumeros(main,ctx){
 const {n,button,field,formPanel,configured,db,result,guard,can,account,write,error,refresh}=ctx;
 const editable=configured&&can(account?.role,'content');
 main.append(n('p','Numéros affichés dans la rubrique « Numéros utiles » de Koki Connect. Indiquez toujours la source. Les numéros d’urgence intégrés à l’application restent affichés en secours.'));
 let rows=[];
 async function edit(row,initial){await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');const old=row?K.decode(row):initial||{};
  main.replaceChildren(n('h1',row?'Modifier un numéro':'Ajouter un numéro'));const f=formPanel(),m={};
  field(f,m,'titre','Nom du service','text',null,row?.titre||old.titre||'',true);
  field(f,m,'groupe','Groupe','text',K.groupes,old.groupe||K.groupes[1],true);
  field(f,m,'telephone','Téléphone (+221 33 000 00 00, ou numéro court : 17)','tel',null,old.telephone||'',true);
  field(f,m,'description','Description courte (300 caractères maximum)','textarea',null,old.description||'');
  field(f,m,'source','Source (obligatoire)','text',null,row?.source||old.source||'',true);
  field(f,m,'verifie_le','Date de vérification','date',null,old.verifie_le||new Date().toISOString().slice(0,10));
  field(f,m,'statut','Visibilité','text',['brouillon','publié'],row?.statut||'brouillon',true);
  field(f,m,'publication','Date de publication (heure de Koki)','datetime-local',null,(row?.publication||new Date().toISOString()).slice(0,16),true);
  m.description.maxLength=300;m.titre.maxLength=180;
  const submit=n('button','Enregistrer le numéro');submit.type='submit';submit.className='primary';f.append(submit,button('Annuler',refresh));
  f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{await guard();const v=Object.fromEntries(Object.entries(m).map(([k,x])=>[k,x.value.trim()]));const data=construireLigne(v);
   const memes=doublons(rows,v.telephone,row?.id);if(memes.length&&!confirm('Ce numéro existe déjà : « '+memes.map(x=>x.titre).join(', ')+' ». Enregistrer quand même ?'))return;
   await write('koki_contents',data,row);await refresh();}catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(f);}
 const add=button('Ajouter un numéro',()=>edit(),'primary');add.disabled=!editable;
 const importer=button('Importer les numéros d’urgence nationaux (brouillons)',async()=>{await guard();const manquants=urgencesNationales.filter(x=>!rows.some(r=>K.decode(r)&&chiffres(K.decode(r).telephone)===chiffres(x.telephone)));if(!manquants.length)throw Error('Les numéros d’urgence nationaux sont déjà enregistrés.');if(!confirm(manquants.length+' numéro(s) seront créés en brouillon. Relisez-les avant publication. Continuer ?'))return;for(const x of manquants)await write('koki_contents',construireLigne({...x,statut:'brouillon'}));await refresh();});importer.disabled=!editable;
 main.append(add,importer,button('Actualiser',refresh));
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 for(let offset=0;;offset+=200){const page=await result(db.from('koki_contents').select('*').eq('type',K.type).eq('categorie',K.categorie).order('id').range(offset,offset+199));rows.push(...page.filter(K.decode));if(page.length<200)break;}
 if(!main.isConnected)return;
 const search=n('input');search.type='search';search.placeholder='Rechercher un service ou un numéro…';search.setAttribute('aria-label','Rechercher un numéro utile');const filtre=n('select');filtre.setAttribute('aria-label','Filtrer par état');for(const x of ['Tous','Publié','Brouillon','Programmé','Archivé']){const o=n('option',x);o.value=x;filtre.append(o);}
 main.append(search,filtre);const grid=n('div');grid.className='list';main.append(grid);
 function show(){grid.replaceChildren();const q=search.value.toLocaleLowerCase('fr').trim(),qc=chiffres(q);
  const found=rows.filter(r=>{const v=K.decode(r);return (filtre.value==='Tous'||etat(r)===filtre.value)&&(!q||(r.titre+' '+v.groupe+' '+v.description).toLocaleLowerCase('fr').includes(q)||(qc&&chiffres(v.telephone).includes(qc)));})
   .sort((a,b)=>K.groupes.indexOf(K.decode(a).groupe)-K.groupes.indexOf(K.decode(b).groupe)||a.titre.localeCompare(b.titre,'fr'));
  for(const row of found){const v=K.decode(row),card=n('article');card.className='card';card.append(n('h2',row.titre),n('p',etat(row)+' · '+v.groupe+' · '+v.telephone));if(v.description)card.append(n('p',v.description));card.append(n('p','Source : '+(row.source||'non renseignée')+(v.verifie_le?' · vérifié le '+v.verifie_le:'')));
   if(!v.archive&&doublons(rows,v.telephone,row.id).length)card.append(n('p','⚠ Même numéro qu’une autre fiche active.'));
   const modify=button('Modifier',()=>edit(row));modify.disabled=!editable;card.append(modify);
   const toggle=v.archive?button('Réactiver (brouillon)',async()=>{await guard();await write('koki_contents',{statut:'brouillon',texte:K.encode({...v,archive:false})},row);await refresh();}):button('Archiver',async()=>{if(!confirm('Archiver ce numéro et le retirer de l’application publique ?'))return;await guard();await write('koki_contents',{statut:'brouillon',texte:K.encode({...v,archive:true})},row);await refresh();});
   toggle.disabled=!editable;card.append(toggle);grid.append(card);}
  if(!found.length)grid.append(n('p',rows.length?'Aucun numéro ne correspond à cette recherche.':'Aucun numéro enregistré. Utilisez « Importer les numéros d’urgence nationaux » pour commencer.'));}
 search.oninput=show;filtre.onchange=show;show();
}
