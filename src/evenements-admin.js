// Événements : fiche événement (type, début, fin, lieu, GPS, organisateur, contact, entrée, programme, affiche).
// Même table que le reste : koki_contents, type Événements ; début = colonne evenement, lieu = colonne lieu,
// le reste dans texte (contrat koki.evenement.fiche, voir evenement-contract.js). Aucune migration.
// Un événement terminé disparaît automatiquement de l'application publique.
import './evenement-contract.js';
import {bindImageProcessing} from './image-processing.js';
import {saveImageRecord} from './images.js';
import {positionField} from './position-gps.js';
import {utc} from './model.js';
const E=globalThis.KokiEvenementContract;
const local=iso=>{const t=Date.parse(iso);return Number.isNaN(t)?'':new Date(t).toISOString().slice(0,16);};

export function etatEvenement(row,v,now=Date.now()){
 if(v?.archive)return 'Archivé';if(row.statut!=='publié')return 'Brouillon';
 const e=E.etat(row,v,now);return e==='Sans date'?'Brouillon':e;
}
export function bilanEvenements(rows,now=Date.now()){
 const b={aVenir:0,enCours:0,semaine:0,termines:0,brouillons:0};
 for(const row of rows){const v=E.decode(row),s=etatEvenement(row,v,now);
  if(s==='À venir')b.aVenir++;if(s==='En cours')b.enCours++;if(s==='Terminé')b.termines++;if(s==='Brouillon')b.brouillons++;
  if((s==='À venir'||s==='En cours')&&E.periode('Cette semaine',row,v,now))b.semaine++;}
 return b;
}

export async function renderEvenements(main,ctx){
 const {n,button,field,formPanel,configured,db,result,guard,can,account,write,media,imageURL,imagePreview,error,refresh}=ctx;
 const editable=configured&&can(account?.role,'content');
 main.append(n('p','Agenda de la rubrique « Événements » de l’application : date et heure, lieu, organisateur, programme et affiche. Les habitants peuvent l’ajouter à leur agenda, obtenir l’itinéraire et le partager. Un événement terminé disparaît de lui-même de l’application.'));
 async function edit(row){
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  const v=E.decode(row)||{genre:'Autre',fin:'',organisateur:'',contact:'',entree:'',programme:'',latitude:null,longitude:null};
  main.replaceChildren(n('h1',row?'Modifier un événement':'Publier un événement'));const f=formPanel(),x={};
  if(row&&!E.decode(row)&&row.texte)f.append(n('p','Ancien événement (texte libre) : le texte est repris dans « Programme ». Vérifiez-le avant d’enregistrer.'));
  field(f,x,'titre','Titre (ex. Grand Magal de Koki)','text',null,row?.titre||'',true);
  field(f,x,'genre','Type d’événement','text',E.genres.map(g=>g.nom),v.genre,true);
  field(f,x,'debut','Début (heure de Koki)','datetime-local',null,local(row?.evenement),true);
  field(f,x,'fin','Fin (facultatif — sinon 4 h après le début)','datetime-local',null,local(v.fin));
  field(f,x,'lieu','Lieu (ex. Grande mosquée de Koki)','text',null,row?.lieu||'',true);
  positionField(f,x,{latitude:v.latitude,longitude:v.longitude},{onError:error});
  field(f,x,'organisateur','Organisateur','text',null,v.organisateur);
  field(f,x,'contact','Téléphone de l’organisateur (facultatif)','tel',null,v.contact);
  field(f,x,'entree','Entrée (ex. Gratuite, 1 000 FCFA)','text',null,v.entree);
  field(f,x,'resume','Présentation (affichée sur la fiche)','textarea',null,row?.resume||'',true);
  field(f,x,'programme','Programme (une ligne par moment, ex. 16:00 — Accueil)','textarea',null,v.programme||(row&&!E.decode(row)?String(row.texte||'').slice(0,4000):''));
  field(f,x,'source','Source','text',null,row?.source||'');
  field(f,x,'statut','Visibilité','text',['publié','brouillon'],row?.statut||'publié',true);
  field(f,x,'photo','Affiche (facultatif, 10 Mo maximum)','file');
  const preview=n('section');f.append(preview);const previewFile=imagePreview(preview,row?.image_path,imageURL);
  const submit=n('button','Enregistrer l’événement');submit.type='submit';submit.className='primary';const selected=bindImageProcessing(x.photo,preview,previewFile,submit);f.append(submit,button('Annuler',refresh));
  f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{
   await guard();const val=k=>x[k].value.trim();
   if(!val('titre')||!val('resume')||!val('lieu')||!val('debut'))throw Error('Titre, début, lieu et présentation requis.');
   const debut=utc(val('debut')),fin=val('fin')?utc(val('fin')):'';
   if(fin&&Date.parse(fin)<=Date.parse(debut))throw Error('La fin doit être après le début.');
   const texte=E.encode({genre:x.genre.value,fin,organisateur:val('organisateur'),contact:val('contact'),entree:val('entree'),programme:val('programme'),latitude:x.latitude.value,longitude:x.longitude.value,archive:false});
   if(E.termine({type:E.type,evenement:debut},JSON.parse(texte))&&!confirm('Cet événement est déjà terminé : il ne sera pas visible dans l’application. Enregistrer quand même ?'))return;
   const data={type:E.type,categorie:x.genre.value,titre:val('titre'),resume:val('resume'),lieu:val('lieu'),evenement:debut,source:val('source'),statut:val('statut'),publication:row?.statut==='publié'?row.publication:new Date().toISOString(),texte,image_path:row?.image_path||null};
   await saveImageRecord({data,file:selected(),content:true,upload:media,persist:value=>write('koki_contents',value,row),cleanup:path=>result(db.storage.from('koki-media').remove([path]))});
   await refresh();
  }catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(f);
 }
 const actions=n('div');actions.className='quick-actions';const add=button('Publier un événement',()=>edit(null),'primary');add.disabled=!editable;actions.append(add,button('Actualiser',refresh));main.append(actions);
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 const rows=[];for(let offset=0;;offset+=200){const page=await result(db.from('koki_contents').select('*').eq('type',E.type).order('evenement',{ascending:false}).range(offset,offset+199));rows.push(...page);if(page.length<200)break;}
 if(!main.isConnected)return;
 const b=bilanEvenements(rows);const grid=n('div');grid.className='grid dashboard-metrics';
 for(const [t,val,note]of [['À venir',b.aVenir,b.semaine+' cette semaine'],['En cours',b.enCours,'Affichés « En cours »'],['Terminés',b.termines,'Retirés de l’application'],['Brouillons',b.brouillons,'Non visibles']]){const c=n('article');c.className='card metric';const d=n('div');d.append(n('p',t),n('strong',String(val)),n('small',note));c.append(d);grid.append(c);}
 main.append(grid);
 const search=n('input');search.type='search';search.placeholder='Rechercher un titre, un lieu, un organisateur…';search.setAttribute('aria-label','Rechercher un événement');
 const genre=n('select');genre.setAttribute('aria-label','Type');for(const o of ['Tous les types',...E.genres.map(g=>g.nom)])genre.append(n('option',o));
 const etat=n('select');etat.setAttribute('aria-label','État');for(const o of ['À venir et en cours','À venir','En cours','Terminé','Brouillon','Archivé','Tous les états'])etat.append(n('option',o));
 const list=n('div');list.className='list';main.append(search,genre,etat,list);
 const fmt=ms=>new Date(ms).toLocaleString('fr-FR',{timeZone:'Africa/Dakar',weekday:'short',day:'numeric',month:'long',year:'numeric',hour:'2-digit',minute:'2-digit'});
 function show(){list.replaceChildren();const q=search.value.toLocaleLowerCase('fr').trim();
  const xs=rows.filter(r=>{const v=E.decode(r),s=etatEvenement(r,v);return (genre.value==='Tous les types'||v?.genre===genre.value)&&(etat.value==='Tous les états'||(etat.value==='À venir et en cours'?s==='À venir'||s==='En cours':s===etat.value))&&(!q||[r.titre,r.lieu,v?.organisateur].join(' ').toLocaleLowerCase('fr').includes(q));});
  if(etat.value==='À venir et en cours')xs.reverse();// du plus proche au plus lointain
  for(const row of xs){const v=E.decode(row),s=etatEvenement(row,v),bo=E.bornes(row,v),card=n('article');card.className='card'+(s==='En cours'?' evenement-en-cours':s==='Terminé'?' offre-expiree':'');
   card.append(n('h2',E.genre(v?.genre).icone+' '+row.titre),n('p',s+(v?' · '+v.genre:'')+' · '+row.lieu+(v?.organisateur?' · '+v.organisateur:'')),
    n('p',bo?fmt(bo.debut)+(v?.fin?' → '+fmt(bo.fin):''):'Date manquante'),...(v?[]:[n('p','Ancien événement (texte libre) : modifiez-le pour compléter la fiche.')]));
   const mod=button('Modifier',()=>edit(row));mod.disabled=!editable;card.append(mod);
   if(!v?.archive){const pub=button(row.statut==='publié'?'Dépublier':'Publier maintenant',async()=>{await guard();await write('koki_contents',row.statut==='publié'?{statut:'brouillon'}:{statut:'publié',publication:new Date().toISOString()},row);await refresh();});pub.disabled=!editable;card.append(pub);}
   if(v){const arch=button(v.archive?'Restaurer en brouillon':'Archiver (annulé)',async()=>{if(!v.archive&&!confirm('Archiver cet événement et le retirer de l’application ?'))return;await guard();await write('koki_contents',{statut:'brouillon',texte:E.encode({...v,archive:!v.archive})},row);await refresh();});arch.disabled=!editable;card.append(arch);}
   list.append(card);}
  if(!xs.length)list.append(n('p','Aucun événement pour ce filtre.'));}
 search.oninput=show;genre.onchange=show;etat.onchange=show;show();
 if(ctx.open){const cible=rows.find(r=>r.id===ctx.open);if(cible&&editable)await edit(cible);}
}
