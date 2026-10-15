// Services publics : annuaire des services (horaires, téléphone, GPS), guides des démarches et avis officiels.
// Même table que le reste : koki_contents, contrat koki.service.* (voir service-contract.js). Aucune migration.
// Ne publier que des informations publiques et vérifiées auprès du service concerné.
import './service-contract.js';
import {bindImageProcessing} from './image-processing.js';
import {saveImageRecord} from './images.js';
import {positionField} from './position-gps.js';
const S=globalThis.KokiServiceContract;

export function etat(row,archive,now=Date.now()){if(archive)return 'Archivée';if(row.statut==='publié')return Date.parse(row.publication)>now?'Programmée':'Publiée';return 'Brouillon';}
export function problemesService(row,v){
 const p=[];if(v.archive)return p;
 if(!v.telephone)p.push('Pas de téléphone : impossible d’appeler depuis l’application.');
 if(!v.h24&&!v.plages.length)p.push('Horaires non renseignés : « Ouvert maintenant » ne peut pas s’afficher.');
 if(v.latitude===null)p.push('Pas de position GPS : absent de la carte, itinéraire approximatif.');
 return p;
}
export function problemesDemarche(row,v,services=[]){
 const p=[];if(v.archive)return p;
 if(!v.pieces.length)p.push('Aucune pièce à fournir indiquée.');
 if(!v.service&&!row.lieu)p.push('Lieu où s’adresser non indiqué.');
 if(v.service&&!services.some(s=>s.id===v.service))p.push('Le service lié n’existe plus : choisissez-en un autre.');
 return p;
}
export function bilanServices(rows,now=new Date()){
 const b={services:0,ouverts:0,demarches:0,avis:0,aVerifier:0};const services=rows.filter(r=>S.decodeService(r));
 for(const row of rows){const s=S.decodeService(row),d=S.decodeDemarche(row);
  if(s&&!s.archive){if(row.statut==='publié')b.services++;if(row.statut==='publié'&&S.ouvert(s,now)===true)b.ouverts++;if(problemesService(row,s).length)b.aVerifier++;}
  else if(d&&!d.archive){if(row.statut==='publié')b.demarches++;if(problemesDemarche(row,d,services).length)b.aVerifier++;}
  else if(!s&&!d&&S.avis(row)&&row.statut==='publié'&&now.getTime()-Date.parse(row.publication)<30*86400000)b.avis++;}
 return b;
}

export async function renderServicesPublics(main,ctx){
 const {n,button,field,formPanel,configured,db,result,guard,can,account,write,media,imageURL,imagePreview,error,refresh,navigate,editor,vue}=ctx;
 const editable=configured&&can(account?.role,'content');
 const intro={'services-publics':'Annuaire de la rubrique « Services publics » : mairie, sous-préfecture, gendarmerie, électricité, eau, poste… Les horaires saisis permettent d’afficher « Ouvert maintenant » dans l’application.',
  demarches:'Guides des démarches : pièces à fournir, étapes, coût et délai, et service où s’adresser. N’indiquez que des informations vérifiées auprès du service (l’application précise qu’elles sont indicatives).',
  'avis-officiels':'Avis officiels : communiqués et avis importants (coupures d’eau ou d’électricité, campagnes, réunions publiques). Ils s’affichent dans l’onglet « Avis officiels » et, pendant 7 jours, en tête de la rubrique.'}[vue];
 main.append(n('p',intro));
 const onglets=n('div');onglets.className='sous-rubriques';onglets.setAttribute('aria-label','Services publics');
 for(const [k,l] of [['services-publics','🏛️ Annuaire'],['demarches','📄 Démarches'],['avis-officiels','📢 Avis officiels']]){const c=button(l,()=>navigate(k));if(k===vue)c.setAttribute('aria-current','page');onglets.append(c);}
 main.append(onglets);
 let rows=[];
 async function charger(){rows=[];const pages=async q=>{for(let offset=0;;offset+=200){const page=await result(q().order('publication',{ascending:false}).range(offset,offset+199));rows.push(...page);if(page.length<200)break;}};
  await pages(()=>db.from('koki_contents').select('*').in('categorie',[S.categorieService,S.categorieDemarche]));
  await pages(()=>db.from('koki_contents').select('*').eq('type','Annonces').in('categorie',['Communiqué','Avis important']));}
 const services=()=>rows.filter(r=>S.decodeService(r));

 async function editService(row){
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  const old=S.decodeService(row)||{genre:'Mairie',plages:[],services:[],h24:false,latitude:null,longitude:null};
  main.replaceChildren(n('h1',row?'Modifier un service public':'Ajouter un service public'));const f=formPanel(),m={};
  field(f,m,'titre','Nom du service (ex. Mairie de Koki)','text',null,row?.titre||'',true);
  field(f,m,'genre','Type','text',S.genres.map(g=>g.nom),old.genre,true);
  field(f,m,'resume','Présentation courte','textarea',null,row?.resume||'',true);
  field(f,m,'lieu','Village / quartier / adresse','text',null,row?.lieu||'',true);
  field(f,m,'telephone','Téléphone public','tel',null,old.telephone||'');
  field(f,m,'whatsapp','WhatsApp (facultatif)','tel',null,old.whatsapp||'');
  const h24=field(f,m,'h24','Ouvert 24 h/24 (ex. gendarmerie)','checkbox',null,old.h24);
  const bloc=n('fieldset');bloc.className='wide';bloc.append(n('legend','Horaires d’ouverture au public (heure de Koki)'));const plages=[];
  for(let i=0;i<3;i++){const p=old.plages?.[i]||{jours:[],de:'',a:''};const ligne=n('div');ligne.className='horaires-ligne';const jours=[];
   S.jours.forEach((j,k)=>{const l=n('label');const c=n('input');c.type='checkbox';c.checked=p.jours.includes(k);c.setAttribute('aria-label','Plage '+(i+1)+' : '+j);l.append(c,n('span',j));ligne.append(l);jours.push(c);});
   const de=n('input');de.type='time';de.value=p.de;de.setAttribute('aria-label','Plage '+(i+1)+' : ouverture');const a=n('input');a.type='time';a.value=p.a;a.setAttribute('aria-label','Plage '+(i+1)+' : fermeture');
   ligne.append(de,n('span','à'),a);bloc.append(ligne);plages.push({jours,de,a});}
  f.append(bloc);
  field(f,m,'horaires_note','Précision sur les horaires (facultatif, ex. fermé les jours fériés)','text',null,old.horaires_note||'');
  field(f,m,'services','Prestations, séparées par des virgules (ex. État civil, Légalisation)','text',null,(old.services||[]).join(', '));
  const gps={};positionField(f,gps,{latitude:old.latitude,longitude:old.longitude},{onError:error});
  field(f,m,'description','Informations complémentaires (bureau, accès, conseils)','textarea',null,old.description||'');
  field(f,m,'source','Source / responsable de publication','text',null,row?.source||'');
  field(f,m,'statut','Visibilité','text',['publié','brouillon'],row?.statut||'publié',true);
  field(f,m,'photo','Photo (facultatif, 10 Mo maximum)','file');
  const maj=()=>{bloc.disabled=h24.checked;};h24.onchange=maj;maj();
  const preview=n('section');f.append(preview);const previewFile=imagePreview(preview,row?.image_path,imageURL);
  const submit=n('button','Enregistrer le service');submit.type='submit';submit.className='primary';const selected=bindImageProcessing(m.photo,preview,previewFile,submit);f.append(submit,button('Annuler',refresh));
  f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{
   await guard();const v=k=>m[k].value.trim();if(!v('titre')||!v('resume')||!v('lieu'))throw Error('Nom, présentation et adresse requis.');
   const texte=S.encodeService({genre:v('genre'),telephone:v('telephone'),whatsapp:v('whatsapp'),h24:h24.checked,
    plages:plages.filter(p=>p.jours.some(c=>c.checked)||p.de.value||p.a.value).map(p=>({jours:p.jours.map((c,k)=>c.checked?k:-1).filter(k=>k>=0),de:p.de.value,a:p.a.value})),
    horaires_note:v('horaires_note'),services:v('services'),latitude:gps.latitude.value,longitude:gps.longitude.value,description:v('description'),archive:false});
   const data={type:S.type,categorie:S.categorieService,titre:v('titre'),resume:v('resume'),lieu:v('lieu'),source:v('source'),statut:v('statut'),publication:row?.statut==='publié'?row.publication:new Date().toISOString(),texte,image_path:row?.image_path||null};
   await saveImageRecord({data,file:selected(),content:true,upload:media,persist:value=>write('koki_contents',value,row),cleanup:path=>result(db.storage.from('koki-media').remove([path]))});
   await refresh();
  }catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(f);
 }

 async function editDemarche(row){
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  const old=S.decodeDemarche(row)||{domaine:'État civil',pieces:[],etapes:[],cout:'',delai:'',service:'',conseils:''};
  main.replaceChildren(n('h1',row?'Modifier un guide de démarche':'Ajouter un guide de démarche'));const f=formPanel(),m={};
  field(f,m,'titre','Démarche (ex. Extrait d’acte de naissance)','text',null,row?.titre||'',true);
  field(f,m,'domaine','Domaine','text',S.domaines.map(d=>d.nom),old.domaine,true);
  field(f,m,'resume','À quoi sert ce document ? (une ou deux phrases)','textarea',null,row?.resume||'',true);
  field(f,m,'pieces','Pièces à fournir (une par ligne)','textarea',null,old.pieces.join('\n'));
  field(f,m,'etapes','Étapes (une par ligne, dans l’ordre)','textarea',null,old.etapes.join('\n'));
  field(f,m,'cout','Coût (tel qu’affiché par le service, ex. Gratuit)','text',null,old.cout);
  field(f,m,'delai','Délai (ex. Le jour même)','text',null,old.delai);
  const l=n('label','Service où s’adresser (annuaire)');const sel=n('select');sel.id='field-service';sel.append(new Option('— Aucun (indiquer le lieu ci-dessous) —',''));
  for(const s of services())sel.append(new Option(s.titre+' · '+s.lieu,s.id));sel.value=services().some(s=>s.id===old.service)?old.service:'';l.append(sel);f.append(l);
  field(f,m,'lieu','Lieu où s’adresser (si aucun service de l’annuaire)','text',null,row?.lieu||'');
  field(f,m,'conseils','Conseils pratiques (facultatif)','textarea',null,old.conseils);
  field(f,m,'source','Source (service ayant validé les informations)','text',null,row?.source||'');
  field(f,m,'statut','Visibilité','text',['publié','brouillon'],row?.statut||'publié',true);
  const submit=n('button','Enregistrer la démarche');submit.type='submit';submit.className='primary';f.append(submit,button('Annuler',refresh));
  f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{
   await guard();const v=k=>m[k].value.trim();if(!v('titre')||!v('resume'))throw Error('Démarche et présentation requises.');
   const lie=services().find(s=>s.id===sel.value);
   const texte=S.encodeDemarche({domaine:v('domaine'),pieces:m.pieces.value,etapes:m.etapes.value,cout:v('cout'),delai:v('delai'),service:sel.value,conseils:v('conseils'),archive:false});
   const data={type:S.type,categorie:S.categorieDemarche,titre:v('titre'),resume:v('resume'),lieu:v('lieu')||lie?.titre||'',source:v('source'),statut:v('statut'),publication:row?.statut==='publié'?row.publication:new Date().toISOString(),texte,image_path:row?.image_path||null};
   await write('koki_contents',data,row);await refresh();
  }catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(f);
 }

 const actions=n('div');actions.className='quick-actions';
 const add=vue==='services-publics'?button('Ajouter un service public',()=>editService(),'primary'):vue==='demarches'?button('Ajouter un guide de démarche',()=>editDemarche(),'primary'):button('Publier un avis officiel',()=>editor('contents',{type:'Annonces',categorie:'Avis important'},'avis-officiels'),'primary');
 add.disabled=!editable;actions.append(add,button('📞 Numéros utiles',()=>navigate('numeros')),button('📍 Lieux de la carte',()=>navigate('lieux','Services publics')),button('Actualiser',refresh));main.append(actions);
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 await charger();if(!main.isConnected)return;
 const b=bilanServices(rows);const grid=n('div');grid.className='grid dashboard-metrics';
 for(const [t,val,note]of [['Services publiés',b.services,b.ouverts+' ouverts maintenant'],['Guides de démarches',b.demarches,'Publiés'],['Avis officiels',b.avis,'Ces 30 derniers jours'],['À vérifier',b.aVerifier,'Fiches incomplètes']]){const c=n('article');c.className='card metric';const d=n('div');d.append(n('p',t),n('strong',String(val)),n('small',note));c.append(d);grid.append(c);}
 main.append(grid);
 const search=n('input');search.type='search';search.placeholder='Rechercher…';search.setAttribute('aria-label','Rechercher');
 const filtre=n('select');filtre.setAttribute('aria-label','Filtrer');for(const x of ['Tous','Publiés','Brouillons','Archivés','À vérifier'])filtre.append(new Option(x,x));
 const list=n('div');list.className='list';main.append(search,filtre,list);
 const publier=(row)=>{const pub=button(row.statut==='publié'?'Dépublier':'Publier maintenant',async()=>{await guard();await write('koki_contents',row.statut==='publié'?{statut:'brouillon'}:{statut:'publié',publication:new Date().toISOString()},row);await refresh();});pub.disabled=!editable;return pub;};
 const archiver=(row,v,enc)=>{const a=button(v.archive?'Restaurer en brouillon':'Archiver',async()=>{if(!v.archive&&!confirm('Archiver et retirer de l’application ?'))return;await guard();await write('koki_contents',{statut:'brouillon',texte:enc({...v,archive:!v.archive})},row);await refresh();});a.disabled=!editable;return a;};
 const garde=(row,archive,p)=>{const s=etat(row,archive);switch(filtre.value){case 'Publiés':return s==='Publiée';case 'Brouillons':return s==='Brouillon'||s==='Programmée';case 'Archivés':return archive;case 'À vérifier':return p.length>0;default:return true;}};
 function show(){list.replaceChildren();const q=search.value.toLocaleLowerCase('fr').trim();let nb=0;
  for(const row of rows){
   let card=null;
   if(vue==='services-publics'){const v=S.decodeService(row);if(!v)continue;const p=problemesService(row,v);if(!garde(row,v.archive,p)||(q&&!(row.titre+' '+row.lieu+' '+v.genre+' '+v.services.join(' ')).toLocaleLowerCase('fr').includes(q)))continue;
    const o=S.ouvert(v);card=n('article');card.className='card';card.append(n('h2',S.genre(v.genre).icone+' '+row.titre),n('p',etat(row,v.archive)+' · '+v.genre+' · '+row.lieu),n('p',S.horairesTexte(v)+' · '+(o===null?'Statut inconnu':o?'Ouvert maintenant':'Fermé maintenant')),n('p',(v.telephone||'Sans téléphone')+(v.services.length?' · '+v.services.join(', '):'')));
    if(p.length){const ul=n('ul');ul.className='hint';for(const x of p)ul.append(n('li','⚠ '+x));card.append(ul);}
    const mod=button('Modifier',()=>editService(row));mod.disabled=!editable;card.append(mod);if(!v.archive)card.append(publier(row));card.append(archiver(row,v,S.encodeService));}
   else if(vue==='demarches'){const v=S.decodeDemarche(row);if(!v)continue;const p=problemesDemarche(row,v,services());if(!garde(row,v.archive,p)||(q&&!(row.titre+' '+row.resume+' '+v.domaine).toLocaleLowerCase('fr').includes(q)))continue;
    const lie=services().find(s=>s.id===v.service);card=n('article');card.className='card';card.append(n('h2',S.domaine(v.domaine).icone+' '+row.titre),n('p',etat(row,v.archive)+' · '+v.domaine+' · '+v.pieces.length+' pièce(s) · '+v.etapes.length+' étape(s)'),n('p',[v.cout&&'Coût : '+v.cout,v.delai&&'Délai : '+v.delai,'Où : '+(lie?.titre||row.lieu||'non indiqué')].filter(Boolean).join(' · ')));
    if(p.length){const ul=n('ul');ul.className='hint';for(const x of p)ul.append(n('li','⚠ '+x));card.append(ul);}
    const mod=button('Modifier',()=>editDemarche(row));mod.disabled=!editable;card.append(mod);if(!v.archive)card.append(publier(row));card.append(archiver(row,v,S.encodeDemarche));}
   else{if(S.decodeService(row)||S.decodeDemarche(row)||!S.avis(row))continue;if(!garde(row,false,[])||(q&&!(row.titre+' '+row.resume).toLocaleLowerCase('fr').includes(q)))continue;
    card=n('article');card.className='card'+(row.categorie==='Avis important'?' offre-bientot':'');card.append(n('h2',(row.categorie==='Avis important'?'⚠️ ':'📢 ')+row.titre),n('p',row.statut+' · '+row.categorie+' · '+new Date(row.publication).toLocaleDateString('fr-FR',{timeZone:'Africa/Dakar',day:'numeric',month:'long',year:'numeric'})),n('p',row.resume));
    const mod=button('Modifier',()=>editor('contents',row,'avis-officiels'));mod.disabled=!editable;card.append(mod,publier(row));}
   nb++;list.append(card);}
  if(!nb)list.append(n('p','Aucun élément pour ce filtre.'));}
 search.oninput=show;filtre.onchange=show;show();
 if(ctx.open){const cible=rows.find(r=>r.id===ctx.open);if(cible&&editable){if(S.decodeService(cible))await editService(cible);else if(S.decodeDemarche(cible))await editDemarche(cible);}}
}
