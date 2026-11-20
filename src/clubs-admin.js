// Clubs & Académies — administration FAMpro Digital : validation, suspension, création d'une académie pilote,
// invitations, signalements, modération et relais vers le fil principal.
// Toutes les opérations passent par la RPC koki_sport (commandes admin_*) : la base exige la double
// authentification (aal2) et le rôle (superadmin/manager pour les académies, superadmin/editor pour la modération).
// L'administration ne voit JAMAIS les fiches des joueurs (données de mineurs) : aucune commande ne les expose.
import './clubs-contract.js';
const K=globalThis.KokiClubsContract;

export function decisionsPossibles(statut){
 return {'À valider':[['approve','Valider'],['refuse','Refuser']],'Refusé':[['approve','Valider finalement'],['archive','Archiver']],
  'Actif':[['suspend','Suspendre'],['archive','Archiver']],'Suspendu':[['reactivate','Réactiver'],['archive','Archiver']],'Archivé':[]}[statut]||[];
}
export const motifObligatoire=d=>['refuse','suspend','archive'].includes(d);

export async function renderClubs(main,{n,button,db,guard,can,account,error}){
 const peutValider=can(account?.role,'commerce'),peutModerer=can(account?.role,'content');
 const appel=async(command,input={})=>{await guard();const {data,error:e}=await db.rpc('koki_sport',{command,input});if(e)throw Error(e.code==='42501'?'Accès refusé : double authentification et rôle requis.':K.messageErreur(e));return data;};
 const zone=n('div');let filtre='À valider';
 const info=n('p','Les académies gèrent elles-mêmes leurs joueurs, matchs et publications. FAMpro Digital valide les académies, modère et traite les signalements. Les fiches des joueurs (mineurs) ne sont jamais visibles ici.');
 const chips=n('div');chips.className='sous-rubriques';
 for(const [v,l] of [['À valider','⏳ À valider'],['Actif','✅ Actives'],['Suspendu','⛔ Suspendues'],['Refusé','✖ Refusées'],['','Toutes'],['signalements','🚩 Signalements'],['relais','📣 Relais demandés']]){
  const c=button(l,()=>{filtre=v;afficher();});c.dataset.filtre=v;chips.append(c);}
 const actions=n('div');actions.className='actions';const creer=button('➕ Créer une académie pilote',()=>formulaireCreation(),'primary');creer.disabled=!peutValider;actions.append(creer,button('Actualiser',()=>afficher()));
 main.append(info,actions,chips,zone);

 function code(box,inv,nom){const p=n('div');p.className='panel';p.append(n('p','Code d’invitation du responsable (affiché une seule fois, valable 72 h) :'),n('strong',inv.code));
  const a=n('a','Envoyer par WhatsApp');a.href=K.lienWhatsapp(K.messageInvitation(nom,inv.role,inv.code));a.target='_blank';a.rel='noopener';a.className='button';p.append(a);box.prepend(p);}

 function formulaireCreation(){
  const f=n('form');f.className='panel';f.append(n('h2','Nouvelle académie (créée directement active)'));const champs={};
  for(const [k,l,type,opts] of [['nom','Nom','text'],['type','Type','select',K.TYPES],['discipline','Discipline','select',K.DISCIPLINES],['telephone','Téléphone public','tel'],['presentation','Présentation','textarea']]){
   const lab=n('label',l);const el=type==='select'?n('select'):type==='textarea'?n('textarea'):n('input');if(type==='select')for(const o of opts)el.append(Object.assign(n('option',o),{value:o}));else if(type!=='textarea')el.type=type;
   if(k==='nom'){el.required=true;el.maxLength=120;}lab.append(el);champs[k]=el;f.append(lab);}
  const ok=n('button','Créer et générer l’invitation du responsable');ok.type='submit';ok.className='primary';f.append(ok,button('Annuler',()=>f.remove()));
  f.onsubmit=async e=>{e.preventDefault();ok.disabled=true;try{const v=Object.fromEntries(Object.entries(champs).map(([k,el])=>[k,el.value.trim()]));
   if(!K.telephoneValide(v.telephone))throw Error('Téléphone invalide.');const r=await appel('admin_create_club',v);f.remove();await afficher();code(zone,r.invitation_responsable,r.nom);}catch(err){error(err);}finally{ok.disabled=false;}};
  zone.prepend(f);
 }

 async function afficher(){
  for(const c of chips.children)c.setAttribute('aria-current',String(c.dataset.filtre===filtre));
  zone.replaceChildren(n('p','Chargement…'));
  try{
   if(filtre==='signalements')return signalements(await appel('admin_reports',{}));
   if(filtre==='relais')return relais(await appel('admin_posts',{relais:'demandé'}));
   const xs=await appel('admin_clubs',{statut:filtre});zone.replaceChildren();
   if(!xs.length){zone.append(n('p','Aucune académie dans cette catégorie.'));return;}
   for(const c of xs){const card=n('article');card.className='card';
    card.append(n('h3',c.nom),n('span',c.statut),n('p',[c.type,c.discipline,c.localite].filter(Boolean).join(' · ')),
     n('p','Responsables : '+c.responsables+' · Joueurs : '+c.joueurs+' · Signalements ouverts : '+c.signalements+' · Créée le '+new Date(c.created_at).toLocaleDateString('fr-FR')));
    if(c.motif)card.append(n('p','Motif : '+c.motif));if(c.presentation)card.append(n('p',c.presentation.slice(0,300)));
    if(c.telephone)card.append(n('p','Téléphone public : '+c.telephone));
    if(!c.responsables)card.append(n('p','⚠️ Aucun responsable : générez une invitation.'));
    for(const [d,l] of decisionsPossibles(c.statut)){const bt=button(l,async()=>{let motif=null;
      if(motifObligatoire(d)){motif=prompt('Motif (communiqué à l’académie, 5 caractères minimum) :');if(!motif||motif.trim().length<5)return;}
      else if(!confirm(l+' « '+c.nom+' » ?'))return;
      bt.disabled=true;try{await appel('admin_review',{id:c.id,revision:c.revision,decision:d,motif});await afficher();}catch(err){error(err);bt.disabled=false;}},d==='approve'||d==='reactivate'?'primary':d==='archive'?'danger':undefined);
     bt.disabled=!peutValider;card.append(bt);}
    if(['À valider','Actif'].includes(c.statut)){const inv=button('Inviter un responsable',async()=>{try{const r=await appel('admin_invite',{club_id:c.id,role:'responsable'});code(card,r,c.nom);}catch(err){error(err);}});inv.disabled=!peutValider;card.append(inv);}
    zone.append(card);}
  }catch(err){zone.replaceChildren(n('p',err.message));}
 }

 function signalements(xs){zone.replaceChildren();if(!xs.length){zone.append(n('p','Aucun signalement.'));return;}
  for(const r of xs){const card=n('article');card.className='card';
   card.append(n('h3',r.motif+' · '+r.academie),n('span',r.statut),n('p','Cible : '+({club:'page de l’académie',post:'publication',media:'photo / vidéo'}[r.cible_type])+' · '+new Date(r.created_at).toLocaleString('fr-FR')));
   if(r.details)card.append(n('p','Précisions : '+r.details));if(r.note_admin)card.append(n('p','Note : '+r.note_admin));
   for(const s of ['En cours','Traité'].filter(s=>s!==r.statut)){const bt=button(s==='Traité'?'Marquer traité':'Prendre en charge',async()=>{const note=s==='Traité'?(prompt('Note de traitement (facultatif) :')||''):'';
     bt.disabled=true;try{await appel('admin_report_status',{id:r.id,revision:r.revision,statut:s,note});await afficher();}catch(err){error(err);bt.disabled=false;}});bt.disabled=!peutModerer;card.append(bt);}
   if(r.cible_type!=='club'){const m=button('Masquer le contenu',async()=>{const motif=prompt('Motif du masquage (communiqué à l’académie) :');if(!motif||motif.trim().length<5)return;
     try{await appel('admin_hide',{cible_type:r.cible_type,id:r.cible_id,motif});alert('Contenu masqué.');}catch(err){error(err);}},'danger');m.disabled=!peutModerer;card.append(m);}
   zone.append(card);}}

 function relais(xs){zone.replaceChildren(n('p','Publications que les académies proposent au fil principal de Koki Connect. Accepter enregistre la décision ; la reprise dans le fil se fait ensuite depuis « Publications » de la rubrique Sport.'));
  if(!xs.length){zone.append(n('p','Aucune demande en attente.'));return;}
  for(const p of xs){const card=n('article');card.className='card';card.append(n('h3',p.titre),n('span',p.academie),n('p',p.texte.slice(0,600)));
   for(const [d,l] of [['accepte','Accepter'],['refuse','Refuser']]){const bt=button(l,async()=>{bt.disabled=true;try{await appel('admin_relay',{id:p.id,decision:d});await afficher();}catch(err){error(err);bt.disabled=false;}},d==='accepte'?'primary':undefined);bt.disabled=!peutModerer;card.append(bt);}
   const h=button('Masquer',async()=>{const motif=prompt('Motif du masquage :');if(!motif||motif.trim().length<5)return;try{await appel('admin_hide',{cible_type:'post',id:p.id,motif});await afficher();}catch(err){error(err);}},'danger');h.disabled=!peutModerer;card.append(h);
   zone.append(card);}}

 await afficher();
}
