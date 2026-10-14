// Transport · Signalements : problèmes signalés par les clients ou les chauffeurs pendant ou après une course
// (bouton « Sécurité » de l'application). Données du serveur (commandes admin_ride_reports et admin_ride_report_status,
// droit Transport et double authentification exigés par le serveur) : statut Nouveau / En cours / Traité, avec une note
// (obligatoire pour « Traité »), inscrits au journal des opérations.
export const STATUTS=['Nouveau','En cours','Traité'];
// Contrôle avant envoi (le serveur refait les mêmes contrôles).
export function verifierTraitement(statut,note){const t=String(note||'').trim();if(!STATUTS.includes(statut))return 'Statut invalide.';if(t&&(t.length<3||t.length>500))return 'La note doit contenir de 3 à 500 caractères.';if(statut==='Traité'&&!t)return 'Indiquez ce qui a été fait avant de marquer « Traité ».';return '';}
export const MOTIFS=['Sécurité','Comportement','Itinéraire','Prix','Objet perdu','Autre'];
export function bilanSignalements(rows,maintenant=Date.now()){
 const liste=Array.isArray(rows)?rows:[];const parMotif=Object.fromEntries(MOTIFS.map(m=>[m,0]));
 for(const r of liste)if(r.motif in parMotif)parMotif[r.motif]++;
 return {total:liste.length,securite:parMotif['Sécurité'],nouveaux:liste.filter(r=>r.statut==='Nouveau').length,
  semaine:liste.filter(r=>maintenant-Date.parse(r.created_at)<=7*86400000).length,parMotif};
}
// Sécurité d'abord, puis les plus récents.
export function trierSignalements(rows){return [...(Array.isArray(rows)?rows:[])].sort((a,b)=>(b.motif==='Sécurité')-(a.motif==='Sécurité')||Date.parse(b.created_at)-Date.parse(a.created_at));}
const date=v=>new Date(v).toLocaleString('fr-FR',{timeZone:'Africa/Dakar',dateStyle:'medium',timeStyle:'short'});
export async function renderSignalements(main,{n,button,api,guard,can,account}){
 const status=n('p');status.setAttribute('role','status');
 main.append(n('p','Problèmes signalés par les clients et les chauffeurs depuis le bouton « Sécurité » de la rubrique Transport. Les signalements « Sécurité » sont affichés en premier. En cas de danger, orientez vers la Police (17), les Sapeurs-pompiers (18) ou le SAMU (1515).'),status);
 if(!can(account?.role,'transport')){status.textContent='Votre rôle ne permet pas de consulter les signalements.';return;}
 if(!api.enabled){status.textContent='Écran disponible après l’activation du serveur Transport dans l’administration.';return;}
 const filtre=n('select');filtre.setAttribute('aria-label','Filtrer par motif');for(const m of ['Tous les motifs',...MOTIFS])filtre.append(n('option',m));
 const zone=n('div');main.append(filtre,zone);let rows=[];
 function afficher(){
  zone.replaceChildren();const b=bilanSignalements(rows);
  const grid=n('div');grid.className='grid dashboard-metrics com-metrics';
  for(const [label,valeur,note] of [['Signalements',b.total,'100 plus récents'],['Sécurité',b.securite,'À traiter en priorité'],['Nouveaux',b.nouveaux,'Pas encore traités'],['7 derniers jours',b.semaine,'Signalés cette semaine']]){
   const card=n('article');card.className='card metric com-metric';const t=n('div');t.append(n('p',label),n('strong',Number(valeur).toLocaleString('fr-FR')),n('small',note));card.append(t);grid.append(card);}
  zone.append(grid);
  const visibles=trierSignalements(rows).filter(r=>filtre.value==='Tous les motifs'||r.motif===filtre.value);
  if(!visibles.length){zone.append(n('p',rows.length?'Aucun signalement pour ce motif.':'Aucun signalement pour le moment.'));return;}
  for(const r of visibles){
   const card=n('article');card.className='card com-card'+(r.motif==='Sécurité'?' signalement-securite':'');
   card.append(n('h3',r.motif+' · signalé par le '+(r.role==='chauffeur'?'chauffeur':'client')),n('p',date(r.created_at)+' · statut : '+r.statut));
   if(r.details)card.append(n('p','« '+r.details+' »'));
   card.append(n('p','Course '+String(r.ride_id).slice(0,8)+' · '+(r.course_statut||'statut inconnu')+(r.chauffeur?' · chauffeur : '+r.chauffeur:'')));
   if(r.note_admin)card.append(n('p','Note de l’administration'+(r.traite_le?' ('+date(r.traite_le)+')':'')+' : '+r.note_admin));
   card.append(traitement(r));
   zone.append(card);
  }
 }
 // Traitement : statut et note, envoyés au serveur (droit Transport + MFA), puis la liste est rechargée.
 function traitement(r){
  const f=n('form');f.className='signalement-traitement';const id='sig-'+r.id;
  const ls=n('label','Statut');const st=n('select');st.id=id+'-statut';ls.htmlFor=st.id;for(const x of STATUTS){const o=n('option',x);o.value=x;st.append(o);}st.value=STATUTS.includes(r.statut)?r.statut:'Nouveau';
  const ln=n('label','Note (ce qui a été fait)');const note=n('textarea');note.id=id+'-note';ln.htmlFor=note.id;note.maxLength=500;note.rows=2;note.placeholder=r.note_admin?'Laisser vide pour garder la note actuelle':'Ex. Client rappelé, chauffeur averti';
  const ok=n('button','Enregistrer');ok.type='submit';ok.className='com-btn';const msg=n('small');msg.setAttribute('role','status');
  f.append(ls,st,ln,note,ok,msg);
  f.onsubmit=async e=>{e.preventDefault();const erreur=verifierTraitement(st.value,note.value);if(erreur){msg.textContent=erreur;return;}
   ok.disabled=true;msg.textContent='Enregistrement…';
   try{await guard();const t=note.value.trim();await api.run('admin_ride_report_status',{id:r.id,statut:st.value,...(t?{note:t}:{})},'signalement:'+r.id);await charger();}
   catch(err){msg.textContent=err.message;ok.disabled=false;}};
  return f;
 }
 async function charger(){status.textContent='Chargement…';try{await guard();rows=await api.run('admin_ride_reports',{});status.textContent='Données du serveur au '+date(Date.now())+'.';}catch(e){rows=[];status.textContent=e.message;}afficher();}
 filtre.onchange=afficher;main.append(button('Actualiser',charger,'com-btn'));await charger();
}
