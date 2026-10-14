// Sports & ASC : équipes / ASC et matchs (calendrier, scores en direct, résultats). Le classement est calculé.
// Même table que le reste : koki_contents, contrat koki.sport.* (voir sport-contract.js). Aucune migration.
import './sport-contract.js';
import {bindImageProcessing} from './image-processing.js';
import {saveImageRecord} from './images.js';
const S=globalThis.KokiSportContract;

export function etatSport(row,v,now=Date.now()){if(v.archive)return 'Archivé';if(row.statut!=='publié')return 'Brouillon';return Date.parse(row.publication)>now?'Programmé':'Publié';}
// Équipes et matchs lisibles depuis les contenus Sports (brouillons compris, pour l'administration).
export function lireSport(rows){
 const equipes=new Map(),matchs=[];
 for(const row of rows){const e=S.decodeEquipe(row);if(e)equipes.set(row.id,{...e,id:row.id,nom:row.titre,row});}
 for(const row of rows){const m=S.decodeMatch(row);if(m)matchs.push({...m,id:row.id,row,date:row.evenement||row.publication,terrain:row.lieu||''});}
 matchs.sort((a,b)=>a.date.localeCompare(b.date));
 return {equipes,matchs};
}
// Date et heure saisies à l'heure de Koki (Africa/Dakar = UTC toute l'année).
export const versISO=v=>v?new Date(v+'Z').toISOString():null;
export const versChamp=iso=>iso?new Date(iso).toISOString().slice(0,16):'';
const dateCourte=iso=>new Date(iso).toLocaleString('fr-FR',{timeZone:'Africa/Dakar',weekday:'short',day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'});

async function charger(ctx){const {db,result}=ctx;const rows=[];for(let offset=0;;offset+=200){const page=await result(db.from('koki_contents').select('*').eq('type',S.type).in('categorie',['Équipe','Match']).order('id').range(offset,offset+199));rows.push(...page);if(page.length<200)break;}return rows;}
function metriques(n,items){const grid=n('div');grid.className='grid dashboard-metrics';for(const [t,val,note]of items){const c=n('article');c.className='card metric';const d=n('div');d.append(n('p',t),n('strong',String(val)),n('small',note));c.append(d);grid.append(c);}return grid;}
function pastille(n,e){const p=n('span',S.initiales(e.nom));p.className='sport-pastille';const [c1,c2]=e.couleurs;p.style.background=c2?'linear-gradient(135deg,'+c1+' 0 55%,'+c2+' 55% 100%)':c1;return p;}

export async function renderMatchs(main,ctx){
 const {n,button,field,formPanel,configured,guard,can,account,write,error,refresh,navigate}=ctx;
 const editable=configured&&can(account?.role,'content');
 main.append(n('p','Calendrier, scores en direct et résultats des matchs (navétanes, tournois…). Le classement de l’application est calculé à partir des matchs terminés : victoire 3 points, nul 1, défaite 0.'));
 const actions=n('div');actions.className='quick-actions';main.append(actions);
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 const rows=await charger(ctx);if(!main.isConnected)return;const {equipes,matchs}=lireSport(rows);
 const equipesActives=[...equipes.values()].filter(e=>!e.archive).sort((a,b)=>a.nom.localeCompare(b.nom,'fr'));
 async function edit(m){
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  if(equipesActives.length<2){alert('Ajoutez d’abord au moins deux équipes.');navigate('sport-equipes');return;}
  const v=m||{competition:matchs.at(-1)?.competition||'Navétanes '+new Date().getFullYear(),poule:'',journee:'',discipline:'Football',domicile:'',exterieur:'',statut:'À venir',score_domicile:null,score_exterieur:null,commentaire:''};
  main.replaceChildren(n('h1',m?'Modifier un match':'Ajouter un match'));const f=formPanel(),x={};
  field(f,x,'competition','Compétition (ex. Navétanes 2026)','text',null,v.competition,true);
  const liste=n('datalist');liste.id='sport-competitions';for(const c of new Set(matchs.map(y=>y.competition))){const o=n('option');o.value=c;liste.append(o);}f.append(liste);x.competition.setAttribute('list',liste.id);
  field(f,x,'poule','Poule (facultatif, ex. A)','text',null,v.poule);field(f,x,'journee','Journée / tour (facultatif, ex. 3e journée, Finale)','text',null,v.journee);
  field(f,x,'discipline','Discipline','text',S.disciplines,v.discipline,true);
  const noms=equipesActives.map(e=>e.nom);
  field(f,x,'domicile','Équipe à domicile','text',noms,(equipes.get(v.domicile)||equipesActives[0]).nom,true);
  field(f,x,'exterieur','Équipe à l’extérieur','text',noms,(equipes.get(v.exterieur)||equipesActives[1]).nom,true);
  field(f,x,'date','Date et heure du match (heure de Koki)','datetime-local',null,versChamp(m?.date)||'',true);
  field(f,x,'terrain','Terrain / stade','text',null,m?.terrain||'');
  field(f,x,'statut_match','Statut du match','text',S.statuts,v.statut,true);
  field(f,x,'score_domicile','Buts équipe à domicile','number',null,v.score_domicile??'');field(f,x,'score_exterieur','Buts équipe à l’extérieur','number',null,v.score_exterieur??'');
  field(f,x,'commentaire','Résumé du match (facultatif, 500 caractères)','textarea',null,v.commentaire);
  field(f,x,'statut','Visibilité','text',['publié','brouillon'],m?.row.statut||'publié',true);
  const submit=n('button','Enregistrer le match');submit.type='submit';submit.className='primary';f.append(submit,button('Annuler',refresh));
  f.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{
   await guard();const val=k=>x[k].value.trim();const id=nom=>equipesActives.find(t=>t.nom===nom)?.id;
   const dom=id(x.domicile.value),ext=id(x.exterieur.value);
   const texte=S.encodeMatch({competition:val('competition'),poule:val('poule'),journee:val('journee'),discipline:val('discipline'),domicile:dom,exterieur:ext,statut:val('statut_match'),score_domicile:val('score_domicile'),score_exterieur:val('score_exterieur'),commentaire:val('commentaire'),archive:false});
   if(!val('date'))throw Error('Date du match requise.');
   const titre=(x.domicile.value+' – '+x.exterieur.value).slice(0,180);
   const data={type:S.type,categorie:'Match',titre,resume:(val('competition')+(val('journee')?' · '+val('journee'):'')).slice(0,2000),lieu:val('terrain'),evenement:versISO(val('date')),statut:val('statut'),publication:m?.row.statut==='publié'?m.row.publication:new Date().toISOString(),source:'Koki Connect',texte};
   await write('koki_contents',data,m?.row);await refresh();
  }catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(f);
 }
 // Score rapide : +/− et statut, enregistrés d'un geste (pour suivre un match en direct depuis le terrain).
 function scoreRapide(m){
  const box=n('div');box.className='sport-score-rapide';let sd=m.score_domicile??0,se=m.score_exterieur??0,statut=m.statut;
  const aff=n('strong',sd+' – '+se);aff.className='sport-score';
  const maj=()=>{aff.textContent=sd+' – '+se;};
  const pm=(label,fn)=>{const x=button(label,()=>{fn();maj();});x.disabled=!editable;return x;};
  const sel=n('select');sel.setAttribute('aria-label','Statut du match');for(const s of S.statuts){const o=n('option',s);o.value=s;sel.append(o);}sel.value=statut;sel.disabled=!editable;sel.onchange=()=>{statut=sel.value;};
  const ok=button('Enregistrer le score',async()=>{await guard();const texte=S.encodeMatch({...m,statut,score_domicile:statut==='À venir'||statut==='Reporté'?(m.score_domicile===null&&sd===0&&se===0?'':sd):sd,score_exterieur:statut==='À venir'||statut==='Reporté'?(m.score_exterieur===null&&sd===0&&se===0?'':se):se});await write('koki_contents',{texte},m.row);await refresh();},'primary');ok.disabled=!editable;
  box.append(pm('−',()=>{sd=Math.max(0,sd-1);}),pm('+ Dom.',()=>{sd++;}),aff,pm('+ Ext.',()=>{se++;}),pm('−',()=>{se=Math.max(0,se-1);}),sel,ok);return box;
 }
 const add=button('Ajouter un match',()=>edit(),'primary');add.disabled=!editable||equipesActives.length<2;
 actions.append(add,button('👕 Équipes / ASC',()=>navigate('sport-equipes')),button('📰 Actualités sportives',()=>navigate('contenus:'+S.type)),button('Actualiser',refresh));
 if(equipesActives.length<2)main.append(n('p','Ajoutez au moins deux équipes dans « Équipes / ASC » pour programmer des matchs.'));
 const actifs=matchs.filter(m=>!m.archive);
 main.append(metriques(n,[['En direct',actifs.filter(m=>m.statut==='En direct').length,'Scores visibles en direct'],['À venir',actifs.filter(m=>m.statut==='À venir').length,'Programmés'],['Terminés',actifs.filter(m=>m.statut==='Terminé').length,'Comptent au classement'],['Équipes',equipesActives.length,'Équipes / ASC actives']]));
 const filtre=n('select');filtre.setAttribute('aria-label','Filtrer les matchs');for(const o of ['En cours et à venir','En direct','Terminés','Reportés','Brouillons','Archivés','Tous'])filtre.append(n('option',o));
 const list=n('div');list.className='list';main.append(filtre,list);
 function garde(m){const s=etatSport(m.row,m);switch(filtre.value){case 'En cours et à venir':return !m.archive&&(m.statut==='En direct'||m.statut==='À venir');case 'En direct':return !m.archive&&m.statut==='En direct';case 'Terminés':return !m.archive&&m.statut==='Terminé';case 'Reportés':return !m.archive&&m.statut==='Reporté';case 'Brouillons':return s==='Brouillon'||s==='Programmé';case 'Archivés':return m.archive;default:return true;}}
 function show(){list.replaceChildren();const xs=matchs.filter(garde);if(filtre.value==='Terminés'||filtre.value==='Tous')xs.reverse();
  for(const m of xs){const dom=equipes.get(m.domicile),ext=equipes.get(m.exterieur),card=n('article');card.className='card sport-match'+(m.statut==='En direct'?' sport-direct':'');
   const tete=n('div');tete.className='sport-match-tete';if(dom)tete.append(pastille(n,dom));tete.append(n('h2',(dom?.nom||'?')+' – '+(ext?.nom||'?')));if(ext)tete.append(pastille(n,ext));card.append(tete);
   card.append(n('p',m.statut+(m.score_domicile!==null?' · '+m.score_domicile+' – '+m.score_exterieur:'')+' · '+dateCourte(m.date)+(m.terrain?' · '+m.terrain:'')),n('p',m.competition+(m.poule?' · Poule '+m.poule:'')+(m.journee?' · '+m.journee:'')+' · '+etatSport(m.row,m)));
   if(!m.archive)card.append(scoreRapide(m));
   const mod=button('Modifier',()=>edit(m));mod.disabled=!editable;card.append(mod);
   if(!m.archive){const pub=button(m.row.statut==='publié'?'Dépublier':'Publier maintenant',async()=>{await guard();await write('koki_contents',m.row.statut==='publié'?{statut:'brouillon'}:{statut:'publié',publication:new Date().toISOString()},m.row);await refresh();});pub.disabled=!editable;
    const arch=button('Archiver',async()=>{if(!confirm('Archiver ce match ? Il ne comptera plus au classement.'))return;await guard();await write('koki_contents',{statut:'brouillon',texte:S.encodeMatch({...m,archive:true})},m.row);await refresh();});arch.disabled=!editable;card.append(pub,arch);}
   else{const r=button('Restaurer en brouillon',async()=>{await guard();await write('koki_contents',{texte:S.encodeMatch({...m,archive:false})},m.row);await refresh();});r.disabled=!editable;card.append(r);}
   list.append(card);}
  if(!xs.length)list.append(n('p','Aucun match pour ce filtre.'));}
 filtre.onchange=show;show();
 // Aperçu du classement tel que l'application le calcule (matchs publiés seulement).
 const publies=lireSport(rows.filter(r=>r.statut==='publié'));for(const [k,e] of publies.equipes)if(e.archive)publies.equipes.delete(k);
 for(const c of S.competitions(publies.matchs)){for(const poule of c.poules.length?c.poules:['']){
  const p=n('section');p.className='panel';p.append(n('h2','🏆 Classement · '+c.nom+(poule?' · Poule '+poule:'')));
  const t=n('table');t.className='sport-table';const tr=n('tr');for(const h of ['#','Équipe','J','G','N','P','BP','BC','Diff','Pts'])tr.append(n('th',h));t.append(tr);
  for(const r of S.classement(publies.matchs,publies.equipes,{competition:c.nom,poule})){const l=n('tr');for(const v of [r.rang,r.nom,r.j,r.g,r.n,r.p,r.bp,r.bc,(r.diff>0?'+':'')+r.diff,r.pts])l.append(n('td',String(v)));t.append(l);}
  p.append(t);main.append(p);}}
 if(ctx.open){const cible=matchs.find(m=>m.id===ctx.open);if(cible&&editable)await edit(cible);}
}

export async function renderEquipes(main,ctx){
 const {n,button,field,formPanel,configured,guard,can,account,write,media,imageURL,imagePreview,error,refresh,navigate,db,result}=ctx;
 const editable=configured&&can(account?.role,'content');
 main.append(n('p','Équipes et ASC de Koki : nom, couleurs, logo, quartier, contact et effectif. Les matchs et le classement se gèrent dans « Matchs et résultats ».'));
 const actions=n('div');actions.className='quick-actions';main.append(actions);
 if(!configured){main.append(n('p','Connexion requise. Aucune donnée fictive affichée.'));return;}
 const rows=await charger(ctx);if(!main.isConnected)return;const {equipes,matchs}=lireSport(rows);
 async function edit(e){
  await guard();if(!can(account.role,'content'))throw Error('Permission refusée.');
  const v=e||{discipline:'Football',quartier:'',poule:'',couleurs:['#087a3d','#f28c28'],president:'',telephone:'',description:'',joueurs:[]};
  main.replaceChildren(n('h1',e?'Modifier une équipe':'Ajouter une équipe / ASC'));const f=formPanel(),x={};
  field(f,x,'titre','Nom de l’équipe (ex. ASC Jamm)','text',null,e?.nom||'',true);
  field(f,x,'discipline','Discipline','text',S.disciplines,v.discipline,true);
  field(f,x,'quartier','Quartier / village','text',null,v.quartier);field(f,x,'poule','Poule (facultatif)','text',null,v.poule);
  field(f,x,'couleur1','Couleur principale','color',null,v.couleurs[0]);field(f,x,'couleur2','Deuxième couleur','color',null,v.couleurs[1]||v.couleurs[0]);
  field(f,x,'president','Président (facultatif)','text',null,v.president);field(f,x,'telephone','Téléphone de contact (facultatif)','tel',null,v.telephone);
  field(f,x,'description','Présentation (facultatif)','textarea',null,v.description);
  field(f,x,'joueurs','Effectif : un joueur par ligne, « numéro - nom - poste » (ex. 10 - Moussa Diop - Attaquant)','textarea',null,v.joueurs.map(j=>[j.numero??'',j.nom,j.poste].filter((y,i)=>i===1||y!=='').join(' - ')).join('\n'));
  field(f,x,'statut','Visibilité','text',['publié','brouillon'],e?.row.statut||'publié',true);
  field(f,x,'photo','Logo (10 Mo maximum, compression automatique)','file');
  const preview=n('section');f.append(preview);const previewFile=imagePreview(preview,e?.row.image_path,imageURL);
  const submit=n('button','Enregistrer l’équipe');submit.type='submit';submit.className='primary';const selected=bindImageProcessing(x.photo,preview,previewFile,submit);f.append(submit,button('Annuler',refresh));
  f.onsubmit=async ev=>{ev.preventDefault();submit.disabled=true;try{
   await guard();const val=k=>x[k].value.trim();if(!val('titre'))throw Error('Nom de l’équipe requis.');
   const couleurs=[x.couleur1.value,x.couleur2.value];if(couleurs[0]===couleurs[1])couleurs.pop();
   const texte=S.encodeEquipe({discipline:val('discipline'),quartier:val('quartier'),poule:val('poule'),couleurs,president:val('president'),telephone:val('telephone'),description:val('description'),joueurs:x.joueurs.value,archive:false});
   const data={type:S.type,categorie:'Équipe',titre:val('titre'),resume:(val('discipline')+(val('quartier')?' · '+val('quartier'):'')).slice(0,2000),lieu:val('quartier'),statut:val('statut'),publication:e?.row.statut==='publié'?e.row.publication:new Date().toISOString(),source:'Koki Connect',texte,image_path:e?.row.image_path||null};
   await saveImageRecord({data,file:selected(),content:true,upload:media,persist:value=>write('koki_contents',value,e?.row),cleanup:path=>result(db.storage.from('koki-media').remove([path]))});
   await refresh();
  }catch(err){error(err);}finally{submit.disabled=false;}};
  main.append(f);
 }
 const add=button('Ajouter une équipe / ASC',()=>edit(),'primary');add.disabled=!editable;actions.append(add,button('📅 Matchs et résultats',()=>navigate('sport-matchs')),button('Actualiser',refresh));
 const xs=[...equipes.values()].sort((a,b)=>a.archive-b.archive||a.nom.localeCompare(b.nom,'fr'));
 main.append(metriques(n,[['Équipes publiées',xs.filter(e=>etatSport(e.row,e)==='Publié').length,xs.filter(e=>e.archive).length+' archivée(s)'],['Joueurs',xs.reduce((s,e)=>s+(e.archive?0:e.joueurs.length),0),'Dans les effectifs'],['Sans logo',xs.filter(e=>!e.archive&&!e.row.image_path).length,'Pastille de couleur affichée']]));
 const list=n('div');list.className='list';main.append(list);
 for(const e of xs){const card=n('article');card.className='card sport-equipe';const tete=n('div');tete.className='sport-match-tete';tete.append(pastille(n,e),n('h2',e.nom));card.append(tete);
  const joues=matchs.filter(m=>!m.archive&&(m.domicile===e.id||m.exterieur===e.id)).length;
  card.append(n('p',etatSport(e.row,e)+' · '+[e.discipline,e.quartier,e.poule?'Poule '+e.poule:''].filter(Boolean).join(' · ')),n('p',e.joueurs.length+' joueur(s) · '+joues+' match(s)'+(e.telephone?' · '+e.telephone:'')));
  if(e.row.image_path)imagePreview(card,e.row.image_path,imageURL);
  const mod=button('Modifier',()=>edit(e));mod.disabled=!editable;card.append(mod);
  if(!e.archive){const arch=button('Archiver',async()=>{if(!confirm('Archiver « '+e.nom+' » ? Ses matchs ne s’afficheront plus.'))return;await guard();await write('koki_contents',{statut:'brouillon',texte:S.encodeEquipe({...e,archive:true})},e.row);await refresh();});arch.disabled=!editable;card.append(arch);}
  else{const r=button('Restaurer en brouillon',async()=>{await guard();await write('koki_contents',{texte:S.encodeEquipe({...e,archive:false})},e.row);await refresh();});r.disabled=!editable;card.append(r);}
  list.append(card);}
 if(!xs.length)list.append(n('p','Aucune équipe pour le moment.'));
 if(ctx.open){const cible=equipes.get(ctx.open);if(cible&&editable)await edit(cible);}
}
