// Emplois & Opportunités : fiches offre (organisme, contrat, lieu, date limite, comment postuler).
// Même table que le reste : koki_contents, type Opportunités, contrat koki.opportunite.offre (voir offre-contract.js).
// Les offres dont la date limite est passée disparaissent automatiquement de l'application.
import './offre-contract.js';
import {bindImageProcessing} from './image-processing.js';
import {saveImageRecord} from './images.js';
const O=globalThis.KokiOffreContract;

export function etatOffre(row,v,now=new Date()){
 if(v?.archive)return 'Archivée';if(row.statut!=='publié')return 'Brouillon';
 if(v&&O.expiree(v,now))return 'Expirée';if(Date.parse(row.publication)>now.getTime())return 'Programmée';
 const j=v?O.joursRestants(v,now):null;return j!==null&&j<=7?'Se termine bientôt':'En ligne';
}
export function bilanOffres(rows,now=new Date()){
 const b={enLigne:0,bientot:0,expirees:0,brouillons:0,sansDate:0};
 for(const row of rows){const v=O.decode(row),s=etatOffre(row,v,now);
  if(s==='En ligne'||s==='Se termine bientôt')b.enLigne++;if(s==='Se termine bientôt')b.bientot++;if(s==='Expirée')b.expirees++;if(s==='Brouillon'||s==='Programmée')b.brouillons++;
  if((s==='En ligne'||s==='Se termine bientôt')&&!v?.date_limite)b.sansDate++;}
 return b;
}

export async function renderOffres(main,ctx){
 const {n,button,field,formPanel,configured,db,result,guard,can,account,write,media,imageURL,imagePreview,error,refresh}=ctx;
 const editable=configured&&can(account?.role,'content');
 main.append(n('p','Offres de la rubrique « Emplois & Opportunités » de l’application : emplois, stages, formations, concours, bourses et financements. Indiquez la date limite : l’offre disparaît d’elle-même de l’application le lendemain.'));
 async function edit(row,preset={}){
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  const v=O.decode(row)||{organisme:'',contrat:'',remuneration:'',date_limite:'',comment_postuler:'',description:row?String(row.texte||''):''};
  main.replaceChildren(n('h1',row?'Modifier une offre':'Publier une offre'));const f=formPanel(),x={};
  field(f,x,'titre','Intitulé (ex. Secrétaire de mairie)','text',null,row?.titre||'',true);
  field(f,x,'categorie','Catégorie','text',O.categories,row?.categorie||preset.categorie||'Emploi',true);
  field(f,x,'organisme','Organisme / employeur','text',null,v.organisme);
  field(f,x,'lieu','Lieu (village, ville)','text',null,row?.lieu||'');
  field(f,x,'contrat','Type de contrat (facultatif)','text',O.contrats,v.contrat);
  field(f,x,'remuneration','Rémunération (facultatif, ex. 150 000 FCFA / mois)','text',null,v.remuneration);
  field(f,x,'date_limite','Date limite de candidature','date',null,v.date_limite);
  field(f,x,'resume','Résumé (affiché sur la carte)','textarea',null,row?.resume||'',true);
  field(f,x,'description','Détails de l’offre (missions, profil, conditions)','textarea',null,v.description);
  field(f,x,'comment_postuler','Comment postuler (dossier, adresse, téléphone, lien…)','textarea',null,v.comment_postuler);
  field(f,x,'source','Source','text',null,row?.source||'');
  field(f,x,'statut','Visibilité','text',['publié','brouillon'],row?.statut||'publié',true);
  field(f,x,'photo','Image (facultatif, 10 Mo maximum)','file');
  const preview=n('section');f.append(preview);const previewFile=imagePreview(preview,row?.image_path,imageURL);
  const submit=n('button','Enregistrer l’offre');submit.type='submit';submit.className='primary';const selected=bindImageProcessing(x.photo,preview,previewFile,submit);f.append(submit,button('Annuler',refresh));
  f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{
   await guard();const val=k=>x[k].value.trim();if(!val('titre')||!val('resume'))throw Error('Intitulé et résumé requis.');
   if(val('date_limite')&&val('date_limite')<O.aujourdhui()&&!confirm('La date limite est déjà passée : l’offre ne sera pas visible. Enregistrer quand même ?'))return;
   const texte=O.encode({organisme:val('organisme'),contrat:x.contrat.value,remuneration:val('remuneration'),date_limite:val('date_limite'),comment_postuler:val('comment_postuler'),description:val('description'),archive:false});
   const data={type:O.type,categorie:val('categorie'),titre:val('titre'),resume:val('resume'),lieu:val('lieu'),source:val('source'),statut:val('statut'),publication:row?.statut==='publié'?row.publication:new Date().toISOString(),texte,image_path:row?.image_path||null};
   await saveImageRecord({data,file:selected(),content:true,upload:media,persist:value=>write('koki_contents',value,row),cleanup:path=>result(db.storage.from('koki-media').remove([path]))});
   await refresh();
  }catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(f);
 }
 const actions=n('div');actions.className='quick-actions';const add=button('Publier une offre',()=>edit(null,{categorie:O.familles.find(f=>f.nom===ctx.query)?.categories[0]}),'primary');add.disabled=!editable;actions.append(add,button('Actualiser',refresh));main.append(actions);
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 const rows=[];for(let offset=0;;offset+=200){const page=await result(db.from('koki_contents').select('*').eq('type',O.type).order('publication',{ascending:false}).range(offset,offset+199));rows.push(...page);if(page.length<200)break;}
 if(!main.isConnected)return;
 const b=bilanOffres(rows);const grid=n('div');grid.className='grid dashboard-metrics';
 for(const [t,val,note]of [['En ligne',b.enLigne,b.sansDate+' sans date limite'],['Se terminent bientôt',b.bientot,'Dans 7 jours ou moins'],['Expirées',b.expirees,'Retirées de l’application'],['Brouillons',b.brouillons,'Non visibles']]){const c=n('article');c.className='card metric';const d=n('div');d.append(n('p',t),n('strong',String(val)),n('small',note));c.append(d);grid.append(c);}
 main.append(grid);
 const search=n('input');search.type='search';search.placeholder='Rechercher un intitulé, un organisme, un lieu…';search.setAttribute('aria-label','Rechercher une offre');
 const famille=n('select');famille.setAttribute('aria-label','Catégorie');for(const o of ['Toutes',...O.familles.map(f=>f.nom)])famille.append(n('option',o));if(O.familles.some(f=>f.nom===ctx.query))famille.value=ctx.query;
 const etat=n('select');etat.setAttribute('aria-label','État');for(const o of ['Tous les états','En ligne','Se termine bientôt','Expirée','Brouillon','Archivée'])etat.append(n('option',o));
 const list=n('div');list.className='list';main.append(search,famille,etat,list);
 function show(){list.replaceChildren();const q=search.value.toLocaleLowerCase('fr').trim(),fam=O.familles.find(f=>f.nom===famille.value);
  const xs=rows.filter(r=>{const v=O.decode(r),s=etatOffre(r,v);return (!fam||fam.categories.includes(r.categorie))&&(etat.value==='Tous les états'||(etat.value==='En ligne'?s==='En ligne'||s==='Se termine bientôt':s===etat.value))&&(!q||[r.titre,r.lieu,r.categorie,v?.organisme].join(' ').toLocaleLowerCase('fr').includes(q));});
  for(const row of xs){const v=O.decode(row),s=etatOffre(row,v),card=n('article');card.className='card'+(s==='Se termine bientôt'?' offre-bientot':s==='Expirée'?' offre-expiree':'');
   card.append(n('h2',row.titre),n('p',s+' · '+row.categorie+(v?.contrat?' · '+v.contrat:'')+(v?.organisme?' · '+v.organisme:'')+(row.lieu?' · '+row.lieu:'')),
    n('p',v?.date_limite?'Date limite : '+new Date(v.date_limite+'T12:00:00Z').toLocaleDateString('fr-FR',{timeZone:'Africa/Dakar',day:'numeric',month:'long',year:'numeric'})+(s==='Expirée'?' (passée)':''):(v?'Sans date limite : pensez à la retirer quand elle est pourvue.':'Ancienne offre (texte libre) : modifiez-la pour ajouter une date limite.')));
   const mod=button('Modifier',()=>edit(row));mod.disabled=!editable;card.append(mod);
   if(!v?.archive){const pub=button(row.statut==='publié'?'Dépublier':'Publier maintenant',async()=>{await guard();await write('koki_contents',row.statut==='publié'?{statut:'brouillon'}:{statut:'publié',publication:new Date().toISOString()},row);await refresh();});pub.disabled=!editable;card.append(pub);}
   if(v){const arch=button(v.archive?'Restaurer en brouillon':'Archiver (offre pourvue)',async()=>{if(!v.archive&&!confirm('Archiver cette offre et la retirer de l’application ?'))return;await guard();await write('koki_contents',{statut:'brouillon',texte:O.encode({...v,archive:!v.archive})},row);await refresh();});arch.disabled=!editable;card.append(arch);}
   list.append(card);}
  if(!xs.length)list.append(n('p','Aucune offre pour ce filtre.'));}
 search.oninput=show;famille.onchange=show;etat.onchange=show;show();
 if(ctx.open){const cible=rows.find(r=>r.id===ctx.open);if(cible&&editable)await edit(cible);}
}
