// Administration Commerces & Services : statistiques, file de validation, comparaison des modifications,
// gestion des quatre rubriques. Toutes les règles sont appliquées par le serveur (koki_business) :
// droits Commerce, double authentification, révision exacte, refus de l'auto-validation, chaîne parente.
import './commerce-contract.js';
const C=globalThis.KokiCommerceContract;
const KINDS={professionnels:'Commerces & prestataires',boutiques:'Boutiques',produits:'Produits',services:'Services'};
const SINGULIER={professionnels:'la fiche',boutiques:'la boutique',produits:'le produit',services:'le service'};
const n=(tag,text,className)=>{const e=document.createElement(tag);if(text!==undefined&&text!==null)e.textContent=text;if(className)e.className=className;return e;};
let uid=0;const nid=p=>'com-'+p+'-'+(++uid);
function btn(label,fn,cls='secondary'){const b=n('button',label,'com-btn com-'+cls);b.type='button';b.onclick=fn;return b;}
function labelled(host,label,el,hint){const w=n('div',null,'com-field'),id=nid('f'),l=n('label',label);l.htmlFor=id;el.id=id;w.append(l,el);if(hint){const h=n('p',hint,'com-hint');h.id=id+'-aide';el.setAttribute('aria-describedby',h.id);w.append(h);}host.append(w);return el;}
function select(values,value){const s=n('select');for(const v of values){const o=n('option',v.label??v);o.value=v.value??v;s.append(o);}s.value=value??'';return s;}
function input(type,value){const i=n(type==='textarea'?'textarea':'input');if(type!=='textarea')i.type=type;if(type==='number'){i.inputMode='numeric';i.min='0';i.step='1';}i.value=value??'';return i;}
const date=v=>v?new Date(v).toLocaleString('fr-FR',{timeZone:'Africa/Dakar',day:'numeric',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}):'';
const libelleDecision=d=>({approve:'Approuvée',reject:'Refusée',suspend:'Suspendue',archive:'Archivée',approve_changes:'Modifications approuvées',reject_changes:'Modifications refusées',correction:'Corrigée par l’administration'})[d]||d;
function badge(row){const s=row.statut,lock=row.payload?.moderation_lock;const b=n('span',lock?'Suspendu (administration)':s,'com-badge com-'+(lock?'alerte':({'Actif':'ok','Disponible':'ok','À valider':'attente','En attente':'attente','Refusé':'alerte','Suspendu':'alerte','Fermé':'alerte','Archivé':'neutre','Épuisé':'info','Indisponible':'info','Masqué':'info'})[s]||'neutre'));return b;}
function prix(p,kind){if(kind==='services')return p.tarif==='devis'||p.prix==null?'Sur devis':C.formaterPrix(p.prix);if(kind==='produits')return C.formaterPrix(p.prix)+(p.ancien_prix?' (avant '+C.formaterPrix(p.ancien_prix)+')':'');return '';}
function valeur(v,champ){if(champ==='photos')return (v||[]).length+' photo'+((v||[]).length>1?'s':'');if(champ==='telephone'||champ==='whatsapp')return v?C.afficherTelephone(v):'—';return v??'—';}
function infos(row){
 const p=row.payload||{},dl=n('dl',null,'com-infos');const add=(k,v)=>{if(v!==undefined&&v!==null&&v!==''){dl.append(n('dt',k),n('dd',String(v)));}};
 if(row.kind==='professionnels')add('Activité',p.type);add(row.kind==='services'?'Métier':'Catégorie',p.categorie);
 if(row.kind==='produits'||row.kind==='services')add('Prix',prix(p,row.kind));if(row.kind==='produits')add('Stock',p.stock);
 add('Téléphone',p.telephone&&C.afficherTelephone(p.telephone));add('WhatsApp',p.whatsapp&&C.afficherTelephone(p.whatsapp));
 add('Village ou quartier',p.village);add('Adresse',p.adresse);add('Horaires',p.horaires);add('Zone',p.zone);
 if(p.localisation)add('Position GPS',p.localisation.latitude+', '+p.localisation.longitude);
 if(row.parent)add(row.parent.kind==='boutiques'?'Boutique':'Fiche professionnelle',row.parent.nom+' ('+row.parent.statut+')');
 if(row.professionnel&&row.kind!=='professionnels')add('Professionnel',row.professionnel.nom+(row.professionnel.statut?' ('+row.professionnel.statut+')':''));
 add('Description',p.description);add('Créée le',date(row.created_at));add('Mise à jour',date(row.updated_at));
 add('Visible dans le catalogue',row.publie?'Oui':'Non');
 return dl;
}
function galerie(host,paths,ctx,titre){if(!paths?.length)return;const box=n('div',null,'com-gallery');if(titre)host.append(n('p',titre,'com-label'));for(const p of paths){const fig=n('div',null,'com-photo');ctx.imagePreview(fig,p,ctx.imageURL);box.append(fig);}host.append(box);}
function historique(host,row){if(!row.decisions?.length)return;const d=n('details',null,'com-history');d.append(n('summary','Historique des décisions ('+row.decisions.length+')'));const ul=n('ul');for(const x of row.decisions)ul.append(n('li',date(x.at)+' · '+libelleDecision(x.decision)+(x.avant&&x.apres&&x.avant!==x.apres?' · '+x.avant+' → '+x.apres:'')+(x.note?' · Motif : '+x.note:'')));d.append(ul);host.append(d);}
// Comparaison publiée / proposée, champ par champ, modifications mises en évidence.
function comparaison(host,row,ctx){
 const diff=C.comparerModification(row.payload);if(!diff.length)return;
 const box=n('section',null,'com-diff');box.append(n('h4','Modifications proposées'),n('p','La version publiée reste visible dans le catalogue jusqu’à votre décision.'+(row.payload.modification.soumis_le?' Proposée le '+date(row.payload.modification.soumis_le)+'.':''),'com-hint'));
 const table=n('table');const head=n('tr');for(const h of ['Champ','Actuellement publié','Proposé'])head.append(n('th',h));const thead=n('thead');thead.append(head);table.append(thead);const body=n('tbody');table.append(body);
 for(const d of diff){if(d.champ==='photos'&&!d.modifie&&!d.avant.length)continue;const tr=n('tr',null,d.modifie?'com-changed':'');tr.append(n('th',d.label+(d.modifie?' — modifié':'')));const a=n('td',valeur(d.avant,d.champ)),b=n('td',valeur(d.apres,d.champ));a.dataset.label='Publié';b.dataset.label='Proposé';tr.append(a,b);body.append(tr);}
 box.append(table);
 const photos=diff.find(d=>d.champ==='photos');if(photos?.modifie){galerie(box,photos.avant,ctx,'Photos publiées');galerie(box,photos.apres,ctx,'Photos proposées');}
 host.append(box);
}
async function run(ctx,command,input,operation){await ctx.guard();return ctx.api.run(command,input,operation);}
// Décision avec confirmation ; motif obligatoire pour un refus, conseillé pour une suspension ou un archivage.
function decisionForm(host,row,ctx,{changes=false,onDone}){
 const box=n('div',null,'com-decision');const note=input('textarea','');note.maxLength=500;note.rows=2;
 labelled(box,'Motif (obligatoire pour un refus, visible par le professionnel)',note);
 const actions=n('div',null,'com-actions');box.append(actions);const msg=n('p',null,'com-msg');msg.setAttribute('role','status');box.append(msg);
 const decide=(decision,label,cls)=>{const b=btn(label,async()=>{
   const motif=note.value.trim();if(decision.startsWith('reject')&&motif.length<3){msg.textContent='Indiquez le motif du refus.';note.focus();return;}
   if(!confirm(label+' — '+row.payload.nom+' ?'))return;
   for(const x of actions.querySelectorAll('button'))x.disabled=true;
   try{const input={id:row.id,revision:row.revision,...(motif?{note:motif}:{})};
    if(changes)await run(ctx,'review_changes',{...input,decision:decision.replace('_changes','')},'changes:'+row.id+':'+row.revision);
    else await run(ctx,'moderate',{...input,decision},'moderate:'+row.id+':'+row.revision);
    msg.textContent='Décision enregistrée : '+label+'.';await onDone?.();
   }catch(e){msg.textContent=e.message;for(const x of actions.querySelectorAll('button'))x.disabled=false;}
  },cls);actions.append(b);return b;};
 if(changes){decide('approve_changes','Approuver les modifications','primary');decide('reject_changes','Refuser les modifications','danger');}
 else for(const d of C.decisionsPossibles(row.kind,row.statut)){const b=decide(d,({approve:'Approuver',reject:'Refuser',suspend:'Suspendre',archive:'Archiver'})[d]+' '+SINGULIER[row.kind],d==='approve'?'primary':d==='reject'?'danger':'secondary');
  if(d==='approve'&&row.kind!=='professionnels'&&row.parent&&row.parent.statut!=='Actif'){b.disabled=true;b.title='La fiche parente doit d’abord être approuvée.';box.insertBefore(n('p','Approbation impossible : '+(row.parent.kind==='boutiques'?'la boutique':'la fiche professionnelle')+' « '+row.parent.nom+' » n’est pas approuvée.','com-hint com-warn'),actions);}}
 host.append(box);
}

// 1. Tableau de bord commercial (comptages réels du serveur).
export async function commerceDashboard(host,ctx){
 const sec=n('section',null,'panel com-dashboard');sec.append(n('h2','Commerces & Services'));host.append(sec);
 if(!ctx.api.enabled){sec.append(n('p','Indicateurs disponibles après l’activation du serveur Commerces & Services.'));return;}
 let s;try{await ctx.guard();s=await ctx.api.run('admin_stats',{});}catch(e){sec.append(n('p','Indicateurs indisponibles : '+e.message));return;}
 const grid=n('div',null,'grid dashboard-metrics com-metrics');
 const attente=s.inscriptions_en_attente+s.boutiques_en_attente+s.modifications_en_attente;
 for(const [label,value,note,target] of [
  ['Professionnels inscrits',s.professionnels_inscrits,'Toutes fiches, quel que soit leur statut','professionnels'],
  ['Fiches en attente de validation',attente,s.inscriptions_en_attente+' inscription(s) · '+s.boutiques_en_attente+' boutique(s) · '+s.modifications_en_attente+' modification(s)','validations'],
  ['Boutiques actives',s.boutiques_actives,'Statut Actif','boutiques'],
  ['Produits publiés',s.produits_publies,'Visibles dans le catalogue (disponibles ou épuisés)','produits'],
  ['Services disponibles',s.services_disponibles,'Visibles dans le catalogue','services'],
  ['Fiches suspendues ou archivées',s.suspendus+s.archives,s.suspendus+' suspendue(s) · '+s.archives+' archivée(s)','professionnels']]){
  const card=n('article',null,'card metric com-metric');const text=n('div');text.append(n('p',label),n('strong',Number(value).toLocaleString('fr-FR')),n('small',note));card.append(text);
  if(ctx.can(ctx.account?.role,'commerce'))card.append(btn('Ouvrir : '+label,()=>ctx.navigate(target),'ghost'));grid.append(card);}
 sec.append(grid,n('p','Mesuré le '+date(s.mesure_le)+' · données réelles autorisées, aucune estimation.','com-hint'));
}

// 2 et 3. File de validation centralisée, comparaison des modifications.
export async function renderValidations(main,ctx){
 const status=n('p');status.setAttribute('role','status');main.append(status);
 if(!ctx.can(ctx.account?.role,'commerce')){status.textContent='Votre rôle ne permet pas de valider les fiches commerciales.';return;}
 if(!ctx.api.enabled){status.textContent='Validation disponible après l’activation du serveur Commerces & Services.';return;}
 const zone=n('div',null,'com-queue');main.append(zone);
 async function refresh(){
  zone.replaceChildren(n('p','Chargement…'));let rows;try{await ctx.guard();rows=await ctx.api.run('admin_queue',{});}catch(e){zone.replaceChildren(n('p',e.message));return;}
  zone.replaceChildren(n('p',rows.length?rows.length+' demande(s) à traiter, les plus anciennes en premier.':'Aucune demande en attente.','com-count'),btn('Actualiser',refresh));
  for(const [type,titre] of [['inscription','Nouvelles inscriptions professionnelles'],['boutique','Nouvelles boutiques'],['modification','Modifications de fiches en ligne']]){
   const list=rows.filter(r=>r.demande===type);const sec=n('section',null,'com-group');sec.append(n('h2',titre+' ('+list.length+')'));
   if(!list.length)sec.append(n('p','Rien à traiter.','com-hint'));
   for(const row of list)sec.append(carte(row,ctx,{type,onDone:refresh}));zone.append(sec);}
 }
 await refresh();
}
function carte(row,ctx,{type,onDone}){
 const card=n('article',null,'card com-card');const head=n('div',null,'com-card-head');head.append(n('h3',row.payload.nom),badge(row));card.append(head);
 const sub=[type?C.libellesDemande[type]:KINDS[row.kind],row.payload.village,row.kind!=='professionnels'&&row.professionnel?.nom].filter(Boolean).join(' · ');card.append(n('p',sub,'com-sub'));
 if(row.payload.modification&&!type)card.append(n('p','Modifications en attente de validation','com-badge com-attente'));
 const details=n('div',null,'com-details');details.hidden=true;
 const toggle=btn('Examiner',()=>{details.hidden=!details.hidden;toggle.textContent=details.hidden?'Examiner':'Masquer';toggle.setAttribute('aria-expanded',String(!details.hidden));if(!details.hidden&&!details.childElementCount)remplir();},'primary');toggle.setAttribute('aria-expanded','false');
 card.append(toggle,details);
 function remplir(){
  const changes=row.payload.modification&&row.statut==='Actif';
  if(changes)comparaison(details,row,ctx);
  details.append(n('h4',changes?'Version actuellement publiée':'Informations transmises'),infos(row));galerie(details,row.payload.photos||(row.payload.image_path?[row.payload.image_path]:[]),ctx,'Photos');
  historique(details,row);
  if(ctx.can(ctx.account?.role,'commerce')){
   if(changes)decisionForm(details,row,ctx,{changes:true,onDone});
   if(!type||type!=='modification')decisionForm(details,row,ctx,{onDone});
   if(!type)correction(details,row,ctx,onDone);
  }
 }
 return card;
}

// 4. Gestion des quatre rubriques : recherche, filtres (listes de sélection), fiches détaillées, décisions, corrections.
export async function renderCommerceRubric(main,kind,ctx){
 const status=n('p');status.setAttribute('role','status');main.append(status);
 if(!ctx.can(ctx.account?.role,'commerce')){status.textContent='Votre rôle ne permet pas de gérer cette rubrique.';return;}
 if(!ctx.api.enabled){status.textContent='Gestion disponible après l’activation du serveur Commerces & Services.';return;}
 const filtres=n('form',null,'panel com-filters');filtres.setAttribute('role','search');main.append(filtres);
 const q=labelled(filtres,'Rechercher (nom, catégorie, village, zone)',input('search',''));
 const statuts=[{value:'',label:'Tous'},...C.statuts[kind],...(kind==='professionnels'?['Modification en attente']:[])];
 const st=labelled(filtres,'Statut',select(statuts,''));
 let localites=[];try{localites=(await ctx.api.run('localites',{})).map(x=>x.nom);}catch{localites=[...C.localitesParDefaut];}
 const vil=kind==='produits'||kind==='services'?null:labelled(filtres,'Village ou quartier',select([{value:'',label:'Tous'},...localites],''));
 let parent=null;
 if(kind==='produits'||kind==='services'){
  const parents=await ctx.api.run('admin_records',{kind:kind==='produits'?'boutiques':'professionnels'}).then(r=>r.rows).catch(()=>[]);
  parent=labelled(filtres,kind==='produits'?'Boutique':'Fiche professionnelle',select([{value:'',label:'Toutes'},...parents.map(p=>({value:p.id,label:p.payload.nom+(p.statut!=='Actif'?' ('+p.statut+')':'')}))],''));
 }
 const go=btn('Appliquer les filtres',null,'primary');go.type='submit';filtres.append(go,btn('Réinitialiser',()=>{q.value='';st.value='';if(vil)vil.value='';if(parent)parent.value='';charger(true);}));
 filtres.onsubmit=e=>{e.preventDefault();charger(true);};
 const count=n('p',null,'com-count');count.setAttribute('aria-live','polite');const list=n('div',null,'com-list');const more=n('div');main.append(count,list,more);
 let offset=0,generation=0;
 // Un seul chargement à la fois : un résultat périmé n'est jamais affiché.
 async function charger(reset){
  const g=++generation;if(reset)offset=0;more.replaceChildren();
  const input={kind,offset};if(q.value.trim())input.query=q.value.trim();if(st.value)input.statut=st.value;if(vil?.value)input.village=vil.value;if(parent?.value)input.parent_id=parent.value;
  let res;try{await ctx.guard();res=await ctx.api.run('admin_records',input);}catch(e){status.textContent=e.message;return;}
  if(g!==generation)return;if(reset)list.replaceChildren();
  count.textContent=res.total+' fiche(s) trouvée(s)';for(const row of res.rows)list.append(carte(row,ctx,{onDone:()=>charger(true)}));
  offset+=res.rows.length;if(offset<res.total)more.append(btn('Voir plus ('+(res.total-offset)+')',()=>charger(false)));
 }
 await charger(true);
}

// Correction d'une fiche par l'administration (aucun identifiant saisi ; rattachement inchangé).
function correction(host,row,ctx,onDone){
 const d=n('details',null,'com-correct');d.append(n('summary','Corriger '+SINGULIER[row.kind]));const f=n('form',null,'com-form');f.noValidate=true;d.append(f);host.append(d);
 const p=row.payload,fields={};
 fields.name=labelled(f,'Nom',input('text',p.nom));fields.category=labelled(f,row.kind==='services'?'Métier':'Catégorie',input('text',p.categorie));
 if(row.kind==='professionnels'){fields.phone=labelled(f,'Téléphone',input('tel',p.telephone));}
 if(row.kind==='professionnels'||row.kind==='boutiques'){fields.whatsapp=labelled(f,'WhatsApp (vide : aucun)',input('tel',p.whatsapp));fields.village=labelled(f,'Village ou quartier',select([{value:'',label:'—'},...(C.localitesParDefaut.includes(p.village)||!p.village?[]:[p.village]),...C.localitesParDefaut],p.village||''));fields.address=labelled(f,'Adresse',input('text',p.adresse));fields.hours=labelled(f,'Horaires',input('text',p.horaires));}
 if(row.kind==='professionnels'||row.kind==='services')fields.zone=labelled(f,'Zone d’intervention',input('text',p.zone));
 if(row.kind==='produits'){fields.price=labelled(f,'Prix (FCFA)',input('number',p.prix));fields.old_price=labelled(f,'Ancien prix (FCFA, vide : aucun)',input('number',p.ancien_prix));fields.stock=labelled(f,'Stock',input('number',p.stock));}
 if(row.kind==='services'){fields.pricing=labelled(f,'Tarif',select([{value:'fixe',label:'Prix fixe'},{value:'devis',label:'Sur devis'}],p.tarif||(p.prix==null?'devis':'fixe')));fields.price=labelled(f,'Prix (FCFA, tarif fixe)',input('number',p.prix));}
 fields.description=labelled(f,'Description',input('textarea',p.description));
 const kept=[];const photos=p.photos||(p.image_path?[p.image_path]:[]);
 if(photos.length){const fs=n('fieldset',null,'com-photos');fs.append(n('legend','Photos (décochez pour retirer)'));for(const path of photos){const l=n('label',null,'com-keep'),c=n('input');c.type='checkbox';c.checked=true;const fig=n('div',null,'com-photo');ctx.imagePreview(fig,path,ctx.imageURL);l.append(c,' Conserver');fs.append(fig,l);kept.push({path,c});}f.append(fs);}
 const msg=n('p',null,'com-msg');msg.setAttribute('role','status');
 const save=btn('Enregistrer la correction',async()=>{
  const input={id:row.id,revision:row.revision};const num=el=>el.value.trim()===''?null:Number(el.value);
  const set=(k,v)=>{const before={name:p.nom,category:p.categorie,phone:p.telephone,whatsapp:p.whatsapp,village:p.village,address:p.adresse,hours:p.horaires,zone:p.zone,description:p.description??'',price:p.prix,old_price:p.ancien_prix,stock:p.stock,pricing:p.tarif}[k];if(String(v??'')!==String(before??''))input[k]=v;};
  for(const k of ['name','category','address','hours','zone','description','village'])if(fields[k])set(k,fields[k].value.trim());
  if(fields.phone){const t=C.normaliserTelephone(fields.phone.value);if(!t){msg.textContent='Téléphone invalide.';return;}set('phone',t);}
  if(fields.whatsapp){const w=fields.whatsapp.value.trim()?C.normaliserTelephone(fields.whatsapp.value):null;if(fields.whatsapp.value.trim()&&!w){msg.textContent='WhatsApp invalide.';return;}set('whatsapp',w);}
  if(row.kind==='produits'){for(const k of ['price','old_price','stock'])set(k,num(fields[k]));const e=C.verifierOffre('produits',{nom:fields.name.value,prix:input.price??p.prix,ancien_prix:'old_price' in input?input.old_price:p.ancien_prix,stock:input.stock??p.stock});if(e.length){msg.textContent=e.join(' ');return;}if('price' in input||'old_price' in input||'stock' in input){input.price=input.price??p.prix;input.stock=input.stock??p.stock;}}
  if(row.kind==='services'){set('pricing',fields.pricing.value);if(fields.pricing.value==='fixe'){const v=num(fields.price);if(v===null){msg.textContent='Indiquez le prix du tarif fixe.';return;}if(v!==p.prix||'pricing' in input){input.price=v;input.pricing='fixe';}}else if('pricing' in input)delete input.price;}
  for(const k of Object.keys(input))if(input[k]===''&&['address','hours','zone','category','name'].includes(k)){msg.textContent='Champ vide non accepté : '+k+'.';return;}
  if(kept.length&&kept.some(k=>!k.c.checked))input.photos=kept.filter(k=>k.c.checked).map(k=>k.path);
  if(Object.keys(input).length<=2){msg.textContent='Aucune modification à enregistrer.';return;}
  if(!confirm('Enregistrer la correction de « '+p.nom+' » ?'))return;save.disabled=true;
  try{await run(ctx,'admin_update',input,'correct:'+row.id+':'+row.revision);msg.textContent='Correction enregistrée.';await onDone?.();}catch(e){msg.textContent=e.message;save.disabled=false;}
 },'primary');
 f.append(save,msg);
}
