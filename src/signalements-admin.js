// Transport · Signalements : problèmes signalés par les clients ou les chauffeurs pendant ou après une course
// (bouton « Sécurité » de l'application). Lecture seule ; données du serveur (commande admin_ride_reports,
// droit Transport et double authentification exigés par le serveur).
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
   zone.append(card);
  }
 }
 async function charger(){status.textContent='Chargement…';try{await guard();rows=await api.run('admin_ride_reports',{});status.textContent='Données du serveur au '+date(Date.now())+'.';}catch(e){rows=[];status.textContent=e.message;}afficher();}
 filtre.onchange=afficher;main.append(button('Actualiser',charger,'com-btn'));await charger();
}
