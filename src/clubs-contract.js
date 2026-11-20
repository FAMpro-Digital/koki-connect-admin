// Contrat commun « Clubs & Académies » entre Koki Connect (assets/sport/clubs-contract.js)
// et Koki Connect Admin (src/clubs-contract.js). À conserver IDENTIQUE dans les deux dépôts.
// Les règles qui comptent (droits, consentements, isolation) sont appliquées par le serveur (schéma koki_sport) ;
// ce fichier ne sert qu'à l'affichage et aux contrôles de saisie.
(function(root){'use strict';
const TYPES=['Académie','Club'];
const DISCIPLINES=['Football','Basket-ball','Lutte','Handball','Volley-ball','Athlétisme','Autre'];
const STATUTS_CLUB=['À valider','Actif','Suspendu','Refusé','Archivé'];
const ROLES={responsable:'Responsable',entraineur:'Entraîneur',communication:'Communication'};
const STATUTS_MATCH=['À venir','En direct','Terminé','Reporté','Annulé'];
const STATUTS_SEANCE={'planifiée':'Planifiée','réalisée':'Réalisée','annulée':'Annulée'};
const TYPES_COMPETITION=['Championnat','Coupe','Tournoi','Amical'];
const TYPES_POST=['Actualité','Annonce','Événement','Performance'];
const NOM_PUBLIC={aucun:'Aucun nom affiché',prenom_initiale:'Prénom + initiale (ex. Awa D.)',complet:'Prénom et nom'};
const MODES_CONSENTEMENT={papier:'Formulaire papier signé',oral:'Accord oral',whatsapp:'Message WhatsApp',autre:'Autre'};
const MOTIFS_SIGNALEMENT=['Mineur exposé','Contenu inapproprié','Fausse information','Autre'];
const telRe=/^\+?[0-9 ()-]{6,24}$/,couleurRe=/^#[0-9a-f]{6}$/,uuidRe=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const STATUT_EXPLIQUE={
 'À valider':'Votre demande est en cours d’examen par FAMpro Digital. Vous pouvez déjà préparer votre espace ; rien n’est encore public.',
 'Actif':'Votre académie est visible dans Koki Connect.',
 'Suspendu':'Académie suspendue : votre espace est en lecture seule et la page publique est retirée.',
 'Refusé':'Demande refusée. Consultez le motif ou contactez FAMpro Digital.',
 'Archivé':'Académie archivée.'};

function texte(v,max,min=0){return typeof v==='string'&&v.trim().length>=min&&v.length<=max;}
function telephoneValide(v){return !v||telRe.test(String(v).trim());}
function uuid(v){return typeof v==='string'&&uuidRe.test(v);}
// Code d'invitation : 10 caractères (sans 0/O ni 1/I), affiché XXXXX-XXXXX ; saisie tolérante.
function normaliserCode(v){return String(v||'').toUpperCase().replace(/[^A-Z0-9]/g,'');}
function codeValide(v){return /^[A-HJ-NP-Z2-9]{10}$/.test(normaliserCode(v));}
// Lien YouTube → identifiant (11 caractères) ; null si non reconnu. Aucune autre plateforme acceptée.
function youtubeId(url){
 const s=String(url||'').trim();if(/^[A-Za-z0-9_-]{11}$/.test(s))return s;
 try{const u=new URL(s);const h=u.hostname.replace(/^www\.|^m\./,'');
  if(h==='youtu.be')return /^\/([A-Za-z0-9_-]{11})/.exec(u.pathname)?.[1]||null;
  if(h==='youtube.com'||h==='youtube-nocookie.com'){const v=u.searchParams.get('v');if(v&&/^[A-Za-z0-9_-]{11}$/.test(v))return v;return /^\/(?:embed|shorts|live)\/([A-Za-z0-9_-]{11})/.exec(u.pathname)?.[1]||null;}
 }catch(_){}return null;
}
function lienYoutube(id){return /^[A-Za-z0-9_-]{11}$/.test(id||'')?'https://www.youtube-nocookie.com/embed/'+id+'?rel=0':null;}
function scoreTexte(m){return m&&m.score_domicile!==null&&m.score_domicile!==undefined?m.score_domicile+' – '+m.score_exterieur:'–';}
function issue(m,nomClub){
 if(!m||m.statut!=='Terminé'||m.score_domicile===null||m.score_domicile===undefined)return null;
 const nous=m.domicile===nomClub?'d':m.exterieur===nomClub?'e':null;if(!nous)return null;
 const a=nous==='d'?m.score_domicile:m.score_exterieur,b=nous==='d'?m.score_exterieur:m.score_domicile;
 return a>b?'Victoire':a<b?'Défaite':'Nul';
}
function initiales(nom){return String(nom||'?').split(/\s+/).filter(w=>w&&!/^(de|du|des|la|le|les|et|d’|d')$/i.test(w)).slice(0,2).map(w=>w[0].toUpperCase()).join('')||'?';}
function lienPartage(origine,slug){return String(origine||'').replace(/\/$/,'')+'/?academie='+encodeURIComponent(slug);}
function messageWhatsapp(club,url){return 'Découvrez '+club.nom+' sur Koki Connect : '+url;}
function lienWhatsapp(texte,numero){const n=String(numero||'').replace(/[^0-9]/g,'');return 'https://wa.me/'+(n?(n.length===9?'221'+n:n):'')+'?text='+encodeURIComponent(texte);}
function messageInvitation(club,role,code){return 'Bonjour, vous êtes invité(e) à rejoindre '+club+' sur Koki Connect ('+(ROLES[role]||role)+'). Ouvrez Koki Connect › Sport › Académies › Mon espace académie, puis saisissez le code '+code+' (valable 72 heures, usage unique).';}
// Saisie locale (datetime-local, heure du téléphone) → ISO UTC. Koki est en UTC+0.
function versIso(v){if(!v)return null;const d=new Date(v);return isNaN(d)?null:d.toISOString();}
function versSaisie(iso){if(!iso)return '';const d=new Date(iso);if(isNaN(d))return '';const p=x=>String(x).padStart(2,'0');return d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())+'T'+p(d.getHours())+':'+p(d.getMinutes());}
// Messages serveur techniques → message compréhensible (jamais de détail SQL à l'écran).
function messageErreur(e){const m=String(e&&e.message||e||'');
 if(/violates|constraint|duplicate|invalid input|syntax/i.test(m))return 'Informations invalides ou déjà enregistrées. Vérifiez la saisie.';
 return m||'Une erreur est survenue. Réessayez.';}

const api={TYPES,DISCIPLINES,STATUTS_CLUB,ROLES,STATUTS_MATCH,STATUTS_SEANCE,TYPES_COMPETITION,TYPES_POST,NOM_PUBLIC,MODES_CONSENTEMENT,MOTIFS_SIGNALEMENT,STATUT_EXPLIQUE,
 texte,telephoneValide,uuid,normaliserCode,codeValide,youtubeId,lienYoutube,scoreTexte,issue,initiales,lienPartage,messageWhatsapp,lienWhatsapp,messageInvitation,versIso,versSaisie,messageErreur,couleurValide:v=>couleurRe.test(v)};
if(typeof module==='object'&&module.exports)module.exports=api;else root.KokiClubsContract=Object.freeze(api);
})(typeof window!=='undefined'?window:globalThis);
