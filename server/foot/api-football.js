// Connecteur API-Football (v3, api-sports.io) — CÔTÉ SERVEUR UNIQUEMENT.
// La clé n'est lue que dans l'environnement du serveur (API_FOOTBALL_KEY) : jamais dans le navigateur,
// jamais dans le dépôt, jamais dans une réponse ou un journal (voir expurger()).
// Ce module ne parle qu'au fournisseur et convertit ses réponses au format de public.koki_foot_sync('importer').

export const FOURNISSEUR='api-football';
export const URL_API='https://v3.football.api-sports.io';
const DELAI_MS=8000;

// ───── Erreurs ─────
// Codes alignés sur koki_foot.etat_fournisseurs.derniere_erreur_code.
export class ErreurFournisseur extends Error{
 constructor(code,message,{quotaRestant=null,reessayerApres=null}={}){super(message);this.code=code;this.quotaRestant=quotaRestant;this.reessayerApres=reessayerApres;}
}
// Retire toute trace de clé d'un texte destiné au journal ou à une réponse.
export function expurger(texte,cle){
 let t=String(texte??'');
 if(cle&&cle.length>=8)t=t.split(cle).join('***');
 return t.replace(/(x-apisports-key|x-rapidapi-key|apikey|authorization)\s*[:=]\s*\S+/gi,'$1: ***').slice(0,500);
}
// API-Football répond souvent 200 avec un objet « errors » non vide : à traiter comme une erreur.
export function classerErreurs(errors){
 const e=Array.isArray(errors)?Object.fromEntries(errors.map((v,i)=>[i,v])):(errors||{});
 const cles=Object.keys(e);if(!cles.length)return null;
 const texte=cles.map(k=>k+' : '+e[k]).join(' ; ');
 if(e.token||/token|api key|apikey|subscription|suspended|not subscribed/i.test(texte))return {code:'authentification',texte};
 if(e.requests||e.rateLimit||/limit|quota|too many/i.test(texte))return {code:'quota',texte};
 if(e.plan||/plan|season|access/i.test(texte))return {code:'donnees',texte,plan:true};
 return {code:'donnees',texte};
}
function entier(v){const n=Number(v);return Number.isFinite(n)?Math.trunc(n):null;}

// ───── Client HTTP ─────
// request : fetch injectable (tests). compteur : appelé à chaque requête réellement envoyée.
export function creerClient({cle,request=fetch,base=URL_API,delaiMs=DELAI_MS,compteur=()=>{}}={}){
 if(!cle||typeof cle!=='string'||cle.length<8)throw new ErreurFournisseur('authentification','Clé API-Football absente');
 let quotaRestant=null,quotaJour=null,minuteRestante=null,requetes=0;
 async function appeler(chemin,params={}){
  const u=new URL(chemin,base+'/');
  for(const [k,v] of Object.entries(params))if(v!==undefined&&v!==null&&v!=='')u.searchParams.set(k,String(v));
  if(u.origin!==new URL(base).origin)throw new ErreurFournisseur('autre','Destination refusée');
  let r;
  requetes++;compteur(chemin);
  try{r=await request(u.toString(),{method:'GET',redirect:'error',headers:{'x-apisports-key':cle,accept:'application/json'},signal:AbortSignal.timeout(delaiMs)});}
  catch(e){throw new ErreurFournisseur(e?.name==='TimeoutError'||e?.name==='AbortError'?'delai':'indisponible',expurger(e?.message||'Réseau indisponible',cle));}
  const h=n=>r.headers?.get?.(n);
  quotaRestant=entier(h('x-ratelimit-requests-remaining'))??quotaRestant;
  quotaJour=entier(h('x-ratelimit-requests-limit'))??quotaJour;
  minuteRestante=entier(h('x-ratelimit-remaining'))??minuteRestante;
  if(r.status===429)throw new ErreurFournisseur('quota','Limite de requêtes atteinte (429)',{quotaRestant});
  if(r.status===401||r.status===403)throw new ErreurFournisseur('authentification','Accès refusé par le fournisseur ('+r.status+')');
  if(r.status>=500)throw new ErreurFournisseur('indisponible','Fournisseur indisponible ('+r.status+')');
  if(!r.ok)throw new ErreurFournisseur('donnees','Réponse inattendue ('+r.status+')');
  let corps;try{corps=await r.json();}catch{throw new ErreurFournisseur('donnees','Réponse illisible');}
  const err=classerErreurs(corps?.errors);
  if(err)throw new ErreurFournisseur(err.code,expurger(err.texte,cle),{quotaRestant});
  if(!Array.isArray(corps?.response)&&typeof corps?.response!=='object')throw new ErreurFournisseur('donnees','Réponse sans contenu');
  return corps.response;
 }
 return {
  appeler,
  get quota(){return {restant:quotaRestant,jour:quotaJour,minute:minuteRestante};},
  get requetes(){return requetes;},
  statut:()=>appeler('status'),
  ligues:p=>appeler('leagues',p),
  matchsLigue:(ligue,saison,p={})=>appeler('fixtures',{league:ligue,season:saison,...p}),
  matchsIds:ids=>appeler('fixtures',{ids:ids.join('-')}),
  matchId:id=>appeler('fixtures',{id}),
  classement:(ligue,saison)=>appeler('standings',{league:ligue,season:saison})
 };
}

// ───── Références ─────
// Une compétition API = une ligue ET une saison : ref « <id ligue>:<saison> ».
export const refCompetition=(ligue,saison)=>`${entier(ligue)}:${entier(saison)}`;
export function lireRefCompetition(ref){const m=/^(\d{1,7}):(\d{4})$/.exec(String(ref||''));return m?{ligue:Number(m[1]),saison:Number(m[2])}:null;}
export const libelleSaison=(s,etalee=true)=>etalee?`${s}/${String((s+1)%100).padStart(2,'0')}`:String(s);
const texte=(v,n)=>String(v??'').replace(/\s+/g,' ').trim().slice(0,n);

export function portee(pays){return /^s[ée]n[ée]gal$/i.test(String(pays||''))?'Sénégal':'International';}
export function nomCompetition(ligue){
 const nom=texte(ligue?.name,90)||'Compétition';
 if(portee(ligue?.country)==='Sénégal')return texte(nom+' Sénégal',120);
 if(ligue?.country&&ligue.country!=='World')return texte(`${nom} (${ligue.country})`,120);
 return nom;
}

// ───── Statuts ─────
const STATUTS={TBD:'À venir',NS:'À venir','1H':'En direct','2H':'En direct',LIVE:'En direct',HT:'Mi-temps',ET:'Prolongations',BT:'Prolongations',
 P:'Tirs au but',FT:'Terminé',AET:'Terminé',PEN:'Terminé',AWD:'Terminé',WO:'Terminé',SUSP:'Suspendu',INT:'Interrompu',PST:'Reporté',CANC:'Annulé',ABD:'Annulé'};
export const EN_JEU=new Set(['En direct','Mi-temps','Prolongations','Tirs au but','Interrompu']);
export function statut(court){return STATUTS[String(court||'').toUpperCase()]||null;}

// Score réglementaire, prolongation (buts de la prolongation seulement) et tirs au but.
export function scores(f){
 const st=statut(f?.fixture?.status?.short);const court=String(f?.fixture?.status?.short||'').toUpperCase();
 const g=f?.goals||{},s=f?.score||{};
 const n=v=>(v===null||v===undefined)?null:entier(v);
 const r={score_domicile:null,score_exterieur:null,pro_domicile:null,pro_exterieur:null,tab_domicile:null,tab_exterieur:null};
 if(!st||st==='À venir'||st==='Reporté'||st==='Annulé'&&n(g.home)===null)return r;
 const prolongee=['ET','BT','P','AET','PEN'].includes(court);
 const ftH=n(s.fulltime?.home),ftA=n(s.fulltime?.away);
 if(prolongee&&ftH!==null&&ftA!==null){
  r.score_domicile=ftH;r.score_exterieur=ftA;
  const eH=n(s.extratime?.home),eA=n(s.extratime?.away);
  const gH=n(g.home),gA=n(g.away);
  r.pro_domicile=eH??(gH!==null?Math.max(0,gH-ftH):0);r.pro_exterieur=eA??(gA!==null?Math.max(0,gA-ftA):0);
 }else{r.score_domicile=n(g.home);r.score_exterieur=n(g.away);}
 const pH=n(s.penalty?.home),pA=n(s.penalty?.away);
 if(pH!==null&&pA!==null){r.tab_domicile=pH;r.tab_exterieur=pA;}
 if(r.score_domicile===null||r.score_exterieur===null){
  if(EN_JEU.has(st)){r.score_domicile=r.score_domicile??0;r.score_exterieur=r.score_exterieur??0;}
 }
 return r;
}

export function journee(round){
 const r=texte(round,80);const m=/^Regular Season\s*-\s*(\d+)$/i.exec(r);
 if(m)return 'Journée '+m[1];
 return texte(r.replace(/^Group\s+/i,'Groupe '),40);
}

// ───── Événements ─────
function periodeDe(minute,tab){if(tab)return 'tirs_au_but';if(minute<=45)return 'mi_temps_1';if(minute<=90)return 'mi_temps_2';if(minute<=105)return 'prolongation_1';return 'prolongation_2';}
export function typeEvenement(v){
 const type=String(v?.type||'').toLowerCase(),detail=String(v?.detail||'').toLowerCase(),tab=/shootout/i.test(String(v?.comments||''));
 if(type==='goal'){
  if(tab)return detail.includes('missed')?'tab_manque':'tab_reussi';
  if(detail.includes('missed'))return 'penalty_manque';
  if(detail.includes('own'))return 'but_csc';
  if(detail.includes('penalty'))return 'penalty';
  return 'but';
 }
 if(type==='card'){if(detail.includes('red')||detail.includes('second yellow'))return 'carton_rouge';if(detail.includes('yellow'))return 'carton_jaune';return null;}
 if(type==='subst')return 'remplacement';
 return null; // VAR et autres : non affichés (un but annulé disparaît de la liste complète).
}
// Clé stable : l'API ne fournit pas d'identifiant d'événement. Même événement → même clé à chaque passage ;
// deux événements identiques (rare) sont distingués par leur rang.
export function evenements(f){
 const ref=String(f?.fixture?.id??'');const vus=new Map();const out=[];
 for(const v of Array.isArray(f?.events)?f.events:[]){
  const type=typeEvenement(v);if(!type)continue;
  const tab=type==='tab_reussi'||type==='tab_manque';
  const minute=Math.min(150,Math.max(0,entier(v?.time?.elapsed)??0));
  const add=entier(v?.time?.extra);
  const base=['af',minute,add??0,v?.team?.id??'',type,v?.player?.id??texte(v?.player?.name,40)].join(':');
  const rang=(vus.get(base)||0)+1;vus.set(base,rang);
  out.push({match_ref:ref,cle:texte(base+':'+rang,200),type,periode:periodeDe(minute,tab),minute,minute_add:add===null?null:Math.min(30,Math.max(0,add)),
   equipe_ref:v?.team?.id!=null?String(v.team.id):null,joueur:texte(v?.player?.name,80),joueur2:texte(v?.assist?.name,80)});
 }
 return out;
}

// ───── Conversion d'une liste de matchs ─────
// options.avecEvenements : la réponse contient la liste COMPLÈTE des événements (requête par identifiants) ;
// les événements api absents seront alors retirés (but annulé…), sauf match verrouillé.
export function convertirMatchs(reponse,{porteeCompetition,avecEvenements=false}={}){
 const equipes=new Map(),inscriptions=new Map(),matchs=[],evts=[],complets=[],rejetes=[];
 for(const f of Array.isArray(reponse)?reponse:[]){
  const id=f?.fixture?.id,L=f?.league,H=f?.teams?.home,A=f?.teams?.away;
  const st=statut(f?.fixture?.status?.short);
  if(!id||!L?.id||!L?.season||!H?.id||!A?.id||!st||!f?.fixture?.date){rejetes.push(String(id??'?'));continue;}
  const comp=refCompetition(L.id,L.season);const p=porteeCompetition||portee(L.country);
  for(const t of [H,A]){
   equipes.set(String(t.id),{ref:String(t.id),nom:texte(t.name,80)||'Équipe '+t.id,portee:p});
   inscriptions.set(comp+'|'+t.id,{competition_ref:comp,equipe_ref:String(t.id),poule:''});
  }
  const sc=scores(f);
  if(st==='Terminé'&&(sc.score_domicile===null||sc.score_exterieur===null)){rejetes.push(String(id));continue;}
  const el=entier(f?.fixture?.status?.elapsed);
  const lieu=texte([f?.fixture?.venue?.name,f?.fixture?.venue?.city].filter(Boolean).join(', '),120);
  matchs.push({ref:String(id),competition_ref:comp,domicile_ref:String(H.id),exterieur_ref:String(A.id),date_match:new Date(f.fixture.date).toISOString(),lieu,
   journee:journee(L.round),poule:'',statut:st,minute:EN_JEU.has(st)&&el!==null?Math.min(150,Math.max(0,el)):null,...sc});
  if(avecEvenements&&Array.isArray(f.events)){evts.push(...evenements(f));complets.push(String(id));}
 }
 return {equipes:[...equipes.values()],inscriptions:[...inscriptions.values()],matchs,evenements:evts,evenements_complets:complets,rejetes};
}

// ───── Classement ─────
const FORME={W:'V',D:'N',L:'D'};
export function convertirClassement(reponse,{porteeCompetition}={}){
 const L=(Array.isArray(reponse)?reponse[0]:reponse)?.league;
 if(!L?.id||!L?.season||!Array.isArray(L.standings))return {equipes:[],inscriptions:[],classements:[]};
 const comp=refCompetition(L.id,L.season);const p=porteeCompetition||portee(L.country);
 const groupes=L.standings.filter(Array.isArray);const plusieurs=groupes.length>1;
 const equipes=new Map(),inscriptions=[],classements=[];
 for(const g of groupes)for(const row of g){
  const t=row?.team;if(!t?.id||!entier(row?.rank))continue;
  const poule=plusieurs?texte(String(row.group||'').replace(/^Group\s+/i,'Groupe '),40):'';
  equipes.set(String(t.id),{ref:String(t.id),nom:texte(t.name,80)||'Équipe '+t.id,portee:p});
  inscriptions.push({competition_ref:comp,equipe_ref:String(t.id),poule});
  const a=row.all||{};
  classements.push({competition_ref:comp,poule,equipe_ref:String(t.id),rang:entier(row.rank),joues:entier(a.played)??0,gagnes:entier(a.win)??0,nuls:entier(a.draw)??0,perdus:entier(a.lose)??0,
   buts_pour:entier(a.goals?.for)??0,buts_contre:entier(a.goals?.against)??0,points:entier(row.points)??0,
   forme:String(row.form||'').toUpperCase().split('').map(c=>FORME[c]||'').join('').slice(-5)});
 }
 return {equipes:[...equipes.values()],inscriptions,classements};
}

// Compétition (découverte seulement : nom, saison et type viennent du fournisseur ; publication par l'administrateur).
export function convertirCompetition(entree,saison){
 const L=entree?.league,C=entree?.country;
 const s=(entree?.seasons||[]).find(x=>entier(x.year)===entier(saison));
 if(!L?.id||!s)return null;
 const etalee=String(s.start||'').slice(0,4)!==String(s.end||'').slice(0,4);
 return {ref:refCompetition(L.id,saison),nom:nomCompetition({name:L.name,country:C?.name}),saison:libelleSaison(entier(saison),etalee),
  portee:portee(C?.name),type:String(L.type).toLowerCase()==='cup'?'Coupe':'Championnat'};
}
// Couverture déclarée par le fournisseur pour une saison (avant toute activation).
export function couverture(entree,saison){
 const s=(entree?.seasons||[]).find(x=>entier(x.year)===entier(saison));
 const c=s?.coverage||{};
 return {saison:entier(saison),debut:s?.start||null,fin:s?.end||null,courante:!!s?.current,
  disponible:!!s,evenements:!!c.fixtures?.events,compositions:!!c.fixtures?.lineups,statistiques:!!c.fixtures?.statistics_fixtures,
  classement:!!c.standings,joueurs:!!c.players,buteurs:!!c.top_scorers};
}
