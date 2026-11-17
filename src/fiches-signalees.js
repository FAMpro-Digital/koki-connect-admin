// Commerces & Services · Fiches signalées : produits, services, boutiques et professionnels signalés depuis le bouton
// « Signaler » de l'application publique (Apple, règle 1.2). Données du serveur (koki_record_reports_admin : droit Commerce
// et double authentification exigés par le serveur) : statut Nouveau / En cours / Traité, avec une note (obligatoire pour
// « Traité »), inscrits au journal des opérations. Pour retirer une fiche, l'ouvrir et l'archiver dans son écran habituel.
export const STATUTS=['Nouveau','En cours','Traité'];
export const MOTIFS=['Arnaque ou fraude','Contenu choquant','Produit interdit','Fausses informations','Autre'];
const ECRANS={produits:'produits',services:'services',boutiques:'boutiques',professionnels:'professionnels'};
export function verifierTraitement(statut,note){const t=String(note||'').trim();if(!STATUTS.includes(statut))return 'Statut invalide.';if(t&&(t.length<3||t.length>500))return 'La note doit contenir de 3 à 500 caractères.';if(statut==='Traité'&&!t)return 'Indiquez ce qui a été fait avant de marquer « Traité ».';return '';}
// Nouveaux d'abord, puis les fiches les plus signalées, puis les plus récents.
export function trierFiches(rows){const rang=s=>s==='Nouveau'?0:s==='En cours'?1:2;return [...(Array.isArray(rows)?rows:[])].sort((a,b)=>rang(a.statut)-rang(b.statut)||(b.total||0)-(a.total||0)||Date.parse(b.created_at)-Date.parse(a.created_at));}
const date=v=>new Date(v).toLocaleString('fr-FR',{timeZone:'Africa/Dakar',dateStyle:'medium',timeStyle:'short'});
export async function renderFichesSignalees(main,{n,button,db,guard,can,account,navigate}){
 const section=n('section');section.className='panel';const status=n('p');status.setAttribute('role','status');
 section.append(n('h2','Fiches signalées'),n('p','Fiches signalées par les utilisateurs depuis le bouton « Signaler » de l’application. Vérifiez la fiche, archivez-la si elle enfreint les règles, puis notez ce qui a été fait.'),status);
 main.append(section);
 if(!can(account?.role,'commerce')){status.textContent='Votre rôle ne permet pas de consulter les fiches signalées.';return;}
 const zone=n('div');section.append(zone);
 async function appel(args){await guard();const {data,error}=await db.rpc('koki_record_reports_admin',args);
  if(error)throw Error(error.code==='PGRST202'?'Écran disponible après l’activation des signalements de fiches sur le serveur.':error.code==='42501'?'Droit Commerce et double authentification requis.':String(error.message||'Opération refusée.'));return data;}
 async function charger(){status.textContent='Chargement…';zone.replaceChildren();
  let rows;try{rows=trierFiches(await appel({p_action:'liste'}));}catch(e){status.textContent=e.message;return;}
  const nouveaux=rows.filter(r=>r.statut==='Nouveau').length;status.textContent=rows.length?rows.length+' signalement(s), dont '+nouveaux+' nouveau(x).':'Aucune fiche signalée.';
  for(const r of rows){const card=n('article');card.className='panel';
   card.append(n('h3',r.fiche+' · '+r.kind),n('p',r.motif+' · '+date(r.created_at)+' · '+r.statut+(r.total>1?' · '+r.total+' signalements sur cette fiche':'')+' · fiche '+r.fiche_statut));
   if(r.details)card.append(n('p','Détail : '+r.details));if(r.note_admin)card.append(n('p','Note : '+r.note_admin+(r.traite_le?' ('+date(r.traite_le)+')':'')));
   if(navigate&&ECRANS[r.kind])card.append(button('Ouvrir la fiche',()=>navigate(ECRANS[r.kind],r.fiche)));
   const form=n('form'),sel=n('select'),note=n('textarea'),ok=n('button','Enregistrer'),msg=n('p');sel.setAttribute('aria-label','Statut');for(const s of STATUTS)sel.append(n('option',s));sel.value=r.statut;
   note.maxLength=500;note.placeholder='Ce qui a été fait (obligatoire pour « Traité »)';note.setAttribute('aria-label','Note de traitement');ok.type='submit';msg.setAttribute('role','status');
   form.append(sel,note,ok,msg);form.onsubmit=async e=>{e.preventDefault();const err=verifierTraitement(sel.value,note.value);if(err){msg.textContent=err;return;}ok.disabled=true;
    try{await appel({p_action:'statut',p_id:r.id,p_statut:sel.value,p_note:note.value.trim()||null});await charger();}catch(x){msg.textContent=x.message;ok.disabled=false;}};
   card.append(form);zone.append(card);}
 }
 section.append(button('Actualiser',charger));await charger();
}
