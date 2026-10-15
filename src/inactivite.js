// Déconnexion automatique de l'administration après une période sans activité (poste laissé ouvert).
// Toute action (clic, frappe, défilement, retour sur l'onglet) repousse l'échéance ; le contrôle reprend après une mise en veille.
export const DELAI_INACTIVITE=30*60*1000;
export const expire=(derniere,maintenant,delai=DELAI_INACTIVITE)=>maintenant-derniere>=delai;
export function surveillerInactivite({delai=DELAI_INACTIVITE,actif=()=>true,expirer,cible=globalThis,horloge=()=>Date.now(),intervalle=30000}={}){
 let derniere=horloge(),enCours=false;
 const activite=()=>{derniere=horloge();};
 for(const e of ['pointerdown','keydown','scroll','touchstart'])cible.addEventListener?.(e,activite,{passive:true,capture:true});
 const verifier=async()=>{if(enCours||!actif()){derniere=actif()?derniere:horloge();return false;}if(!expire(derniere,horloge(),delai))return false;enCours=true;try{await expirer();}finally{enCours=false;derniere=horloge();}return true;};
 cible.document?.addEventListener?.('visibilitychange',()=>{if(cible.document.visibilityState==='visible')verifier();});
 const id=setInterval(verifier,intervalle);
 return {verifier,activite,arreter:()=>clearInterval(id)};
}
