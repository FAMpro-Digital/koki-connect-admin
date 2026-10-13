// Santé · Structures de santé (centres, postes, pharmacies, maternités…) partagées avec Koki Connect.
// Même table que le reste : koki_contents, contrat koki.sante.structure (voir sante-contract.js).
import './sante-contract.js';
import {bindImageProcessing} from './image-processing.js';
import {saveImageRecord} from './images.js';
import {positionField} from './position-gps.js';
const S=globalThis.KokiSanteContract;

export function etat(row,archive,now=Date.now()){if(archive)return 'Archivée';if(row.statut==='publié')return Date.parse(row.publication)>now?'Programmée':'Publiée';return 'Brouillon';}
export function problemesSante(row,v){
 const p=[];if(v.archive)return p;
 if(!v.telephone)p.push('Pas de téléphone : impossible d’appeler depuis l’application.');
 if(!v.h24&&!v.plages.length)p.push('Horaires non renseignés : le statut « Ouvert » ne peut pas s’afficher.');
 if(v.latitude===null)p.push('Pas de position GPS : absente de la carte et de l’itinéraire.');
 if(!row.image_path)p.push('Pas de photo.');
 if(v.garde&&!v.garde_fin)p.push('Pharmacie de garde sans date de fin.');
 return p;
}
export function bilanSante(rows,now=new Date()){
 const b={total:0,publiees:0,brouillons:0,archivees:0,ouvertes:0,garde:0,aVerifier:0};
 for(const row of rows){const v=S.decode(row);if(!v)continue;b.total++;const s=etat(row,v.archive,now.getTime());
  if(s==='Publiée')b.publiees++;else if(s==='Archivée')b.archivees++;else b.brouillons++;
  if(!v.archive&&S.ouvert(v,now)===true)b.ouvertes++;if(!v.archive&&S.enGarde(v,now))b.garde++;if(problemesSante(row,v).length)b.aVerifier++;}
 return b;
}

export async function renderSante(main,ctx){
 const {n,button,field,formPanel,configured,db,result,guard,can,account,write,media,imageURL,imagePreview,error,refresh,navigate,editor}=ctx;
 const editable=configured&&can(account?.role,'content');
 main.append(n('p','Structures de santé publiées dans la rubrique Santé de Koki Connect. Ne renseignez que des coordonnées professionnelles publiques, jamais d’informations sur des patients.'));

 async function edit(row){
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  const old=S.decode(row)||{genre:'Centre de santé',plages:[],services:[],h24:false,garde:false,latitude:null,longitude:null};
  main.replaceChildren(n('h1',row?'Modifier une structure de santé':'Ajouter une structure de santé'));const f=formPanel(),m={};
  field(f,m,'titre','Nom de la structure','text',null,row?.titre||'',true);
  field(f,m,'genre','Type','text',S.genres,old.genre,true);
  field(f,m,'resume','Présentation courte','textarea',null,row?.resume||'',true);
  field(f,m,'lieu','Village / quartier / adresse','text',null,row?.lieu||'',true);
  field(f,m,'telephone','Téléphone public','tel',null,old.telephone||'');
  field(f,m,'whatsapp','WhatsApp (facultatif)','tel',null,old.whatsapp||'');
  const h24=field(f,m,'h24','Ouvert 24 h/24','checkbox',null,old.h24);
  // Horaires : jusqu'à trois plages (ex. Lun–Ven 8h–17h, Sam 8h–13h).
  const bloc=n('fieldset');bloc.className='wide';bloc.append(n('legend','Horaires d’ouverture (heure de Koki)'));const plages=[];
  for(let i=0;i<3;i++){const p=old.plages?.[i]||{jours:[],de:'',a:''};const ligne=n('div');ligne.className='horaires-ligne';const jours=[];
   S.jours.forEach((j,k)=>{const l=n('label');const c=n('input');c.type='checkbox';c.checked=p.jours.includes(k);c.setAttribute('aria-label','Plage '+(i+1)+' : '+j);l.append(c,n('span',j));ligne.append(l);jours.push(c);});
   const de=n('input');de.type='time';de.value=p.de;de.setAttribute('aria-label','Plage '+(i+1)+' : ouverture');const a=n('input');a.type='time';a.value=p.a;a.setAttribute('aria-label','Plage '+(i+1)+' : fermeture');
   ligne.append(de,n('span','à'),a);bloc.append(ligne);plages.push({jours,de,a});}
  f.append(bloc);
  field(f,m,'horaires_note','Précision sur les horaires (facultatif)','text',null,old.horaires_note||'');
  field(f,m,'services','Services, séparés par des virgules (ex. Consultations, Vaccination)','text',null,(old.services||[]).join(', '));
  const garde=field(f,m,'garde','Pharmacie de garde','checkbox',null,old.garde);
  field(f,m,'garde_fin','Garde jusqu’au (inclus)','date',null,old.garde_fin||'');
  const gps={};positionField(f,gps,{latitude:old.latitude,longitude:old.longitude},{onError:error});
  field(f,m,'description','Informations complémentaires','textarea',null,old.description||'');
  field(f,m,'source','Source / responsable de publication','text',null,row?.source||'');
  field(f,m,'statut','Visibilité','text',['brouillon','publié'],row?.statut||'brouillon',true);
  field(f,m,'publication','Date de publication (heure de Koki)','datetime-local',null,(row?.publication||new Date().toISOString()).slice(0,16),true);
  field(f,m,'photo','Photo (10 Mo maximum, compression automatique)','file');
  const maj=()=>{bloc.disabled=h24.checked;m.garde_fin.closest('label').hidden=!garde.checked;};h24.onchange=maj;garde.onchange=maj;maj();
  const preview=n('section');f.append(preview);const previewFile=imagePreview(preview,row?.image_path,imageURL);
  const submit=n('button','Enregistrer la structure');submit.type='submit';submit.className='primary';const selected=bindImageProcessing(m.photo,preview,previewFile,submit);f.append(submit,button('Annuler',refresh));
  f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{
   await guard();const v=k=>m[k].value.trim();
   if(!v('titre')||!v('resume')||!v('lieu'))throw Error('Nom, présentation et adresse requis.');
   const texte=S.encode({genre:v('genre'),telephone:v('telephone'),whatsapp:v('whatsapp'),h24:h24.checked,
    plages:plages.filter(p=>p.jours.some(c=>c.checked)||p.de.value||p.a.value).map(p=>({jours:p.jours.map((c,k)=>c.checked?k:-1).filter(k=>k>=0),de:p.de.value,a:p.a.value})),
    horaires_note:v('horaires_note'),services:v('services'),garde:garde.checked,garde_fin:v('garde_fin'),latitude:gps.latitude.value,longitude:gps.longitude.value,description:v('description'),archive:false});
   const data={type:'Informations utiles',categorie:'Santé',titre:v('titre'),resume:v('resume'),lieu:v('lieu'),source:v('source'),statut:v('statut'),publication:new Date(v('publication')+'Z').toISOString(),texte,image_path:row?.image_path||null};
   await saveImageRecord({data,file:selected(),content:true,upload:media,persist:value=>write('koki_contents',value,row),cleanup:path=>result(db.storage.from('koki-media').remove([path]))});
   await refresh();
  }catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(f);
 }

 const actions=n('div');actions.className='quick-actions';
 const add=button('Ajouter une structure de santé',()=>edit(),'primary');add.disabled=!editable;
 const alerte=button('Publier une alerte ou campagne Santé',()=>editor('contents',{type:'Annonces',categorie:'Santé'},'sante'));alerte.disabled=!editable;
 actions.append(add,alerte,button('📞 Numéros utiles (groupe Santé)',()=>navigate('numeros')),button('Actualiser',refresh));main.append(actions);
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 const rows=[];for(let offset=0;;offset+=200){const page=await result(db.from('koki_contents').select('*').eq('categorie','Santé').order('id').range(offset,offset+199));rows.push(...page);if(page.length<200)break;}
 if(!main.isConnected)return;
 const structures=rows.filter(r=>S.decode(r)),autres=rows.filter(r=>!S.decode(r)&&!globalThis.KokiNumeroContract?.decode(r));
 const b=bilanSante(structures);
 const grid=n('div');grid.className='grid dashboard-metrics';
 for(const [t,val,note]of [['Structures publiées',b.publiees,b.brouillons+' brouillon(s) · '+b.archivees+' archivée(s)'],['Ouvertes maintenant',b.ouvertes,'Selon les horaires saisis'],['Pharmacies de garde',b.garde,'Visibles en tête de la page Santé'],['À vérifier',b.aVerifier,'Fiches incomplètes']]){const c=n('article');c.className='card metric';const d=n('div');d.append(n('p',t),n('strong',String(val)),n('small',note));c.append(d);grid.append(c);}
 main.append(grid);
 const search=n('input');search.type='search';search.placeholder='Rechercher un nom, un village, un service…';search.setAttribute('aria-label','Rechercher une structure de santé');
 const filtre=n('select');filtre.setAttribute('aria-label','Filtrer les structures');for(const x of ['Toutes','Centres et postes','Pharmacies','Maternités','De garde','Brouillons','Archivées','À vérifier']){const o=n('option',x);o.value=x;filtre.append(o);}
 const list=n('div');list.className='list';main.append(search,filtre,list);
 function garde(row,v){const s=etat(row,v.archive),fam=S.famille(v.genre);switch(filtre.value){case 'Centres et postes':return fam==='centre'&&!v.archive;case 'Pharmacies':return fam==='pharmacie'&&!v.archive;case 'Maternités':return fam==='maternite'&&!v.archive;case 'De garde':return S.enGarde(v)&&!v.archive;case 'Brouillons':return s==='Brouillon'||s==='Programmée';case 'Archivées':return v.archive;case 'À vérifier':return problemesSante(row,v).length>0;default:return true;}}
 function show(){list.replaceChildren();const q=search.value.toLocaleLowerCase('fr');
  const found=structures.filter(r=>{const v=S.decode(r);return garde(r,v)&&(r.titre+' '+r.lieu+' '+v.genre+' '+v.services.join(' ')).toLocaleLowerCase('fr').includes(q);});
  for(const row of found){const v=S.decode(row),o=S.ouvert(v),card=n('article');card.className='card';
   card.append(n('h2',row.titre),n('p',etat(row,v.archive)+' · '+v.genre+' · '+row.lieu),n('p',S.horairesTexte(v)+' · '+(o===null?'Statut inconnu':o?'Ouverte maintenant':'Fermée maintenant')+(S.enGarde(v)?' · De garde':'')),n('p',(v.telephone||'Sans téléphone')+(v.services.length?' · '+v.services.join(', '):'')));
   const p=problemesSante(row,v);if(p.length){const ul=n('ul');ul.className='hint';for(const x of p)ul.append(n('li','⚠ '+x));card.append(ul);}
   if(row.image_path)imagePreview(card,row.image_path,imageURL);
   const modifier=button('Modifier',()=>edit(row));modifier.disabled=!editable;card.append(modifier);
   if(!v.archive){
    if(S.famille(v.genre)==='pharmacie'){const g=button(v.garde?'Retirer la garde':'Mettre de garde 7 jours',async()=>{await guard();const fin=new Date(Date.now()+6*86400000).toISOString().slice(0,10);await write('koki_contents',{texte:S.encode({...v,garde:!v.garde,garde_fin:v.garde?'':fin})},row);await refresh();});g.disabled=!editable;card.append(g);}
    const pub=button(row.statut==='publié'?'Dépublier':'Publier maintenant',async()=>{await guard();if(row.statut!=='publié'&&!confirm('Publier « '+row.titre+' » dans l’application maintenant ?'))return;await write('koki_contents',row.statut==='publié'?{statut:'brouillon'}:{statut:'publié',publication:new Date().toISOString()},row);await refresh();});pub.disabled=!editable;
    const arch=button('Archiver',async()=>{if(!confirm('Archiver cette structure et la retirer de l’application ?'))return;await guard();await write('koki_contents',{statut:'brouillon',texte:S.encode({...v,archive:true})},row);await refresh();});arch.disabled=!editable;card.append(pub,arch);
   }else{const r=button('Restaurer en brouillon',async()=>{await guard();await write('koki_contents',{statut:'brouillon',texte:S.encode({...v,archive:false})},row);await refresh();});r.disabled=!editable;card.append(r);}
   list.append(card);}
  if(!found.length)list.append(n('p','Aucune structure pour ce filtre.'));}
 search.oninput=show;filtre.onchange=show;show();
 const panel=n('section');panel.className='panel';panel.append(n('h2','Alertes et campagnes Santé'),n('p','Publications de la catégorie Santé (campagnes, avis, alertes). Elles s’affichent dans la page Santé de l’application.'));
 for(const row of autres.slice(0,30)){const r=n('article');r.className='dashboard-row';r.append(n('strong',row.titre),n('small',row.type+' · '+row.statut+' · '+new Date(row.publication).toLocaleDateString('fr-FR',{timeZone:'Africa/Dakar'})));const e=button('Modifier',()=>editor('contents',row,'sante'));e.disabled=!editable;r.append(e);panel.append(r);}
 if(!autres.length)panel.append(n('p','Aucune alerte ou campagne Santé publiée.'));
 main.append(panel);
 if(ctx.open){const cible=structures.find(r=>r.id===ctx.open);if(cible&&editable)await edit(cible);}
}
