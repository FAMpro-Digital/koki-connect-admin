import {createClient} from '@supabase/supabase-js';

// Clé privilégiée uniquement dans l'environnement serveur, jamais dans VITE_*.
export function invitationHandler({client=createClient,env=process.env}={}) {
 return async (req,res)=>{
  res.setHeader('Cache-Control','no-store');
  if(req.method!=='POST')return res.status(405).json({error:'Méthode refusée.'});
  const url=env.SUPABASE_URL,key=env.SUPABASE_SERVICE_ROLE_KEY,origin=env.KOKI_ADMIN_ORIGIN;
  if(!url||!key||!origin)return res.status(503).json({error:'Les invitations ne sont pas encore configurées sur le serveur.'});
  let redirect;try{redirect=new URL('/?action=invite',origin);if(redirect.protocol!=='https:')throw Error();}catch{return res.status(503).json({error:'Adresse administrateur non configurée.'});}
  if(req.headers.origin!==redirect.origin)return res.status(403).json({error:'Origine refusée.'});
  const token=/^Bearer (\S+)$/.exec(req.headers.authorization||'')?.[1];
  if(!token)return res.status(401).json({error:'Connexion requise.'});
  try{
   const admin=client(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
   const {data,error}=await admin.auth.getUser(token);
   if(error||!data?.user)return res.status(401).json({error:'Session invalide.'});
   // getUser a validé le jeton auprès du serveur Auth avant la lecture du niveau MFA.
   let claims;try{claims=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString('utf8'));}catch{return res.status(401).json({error:'Session invalide.'});}
   const membership=await admin.from('koki_admin_members').select('role,enabled').eq('user_id',data.user.id).maybeSingle();
   if(membership.error||!membership.data?.enabled||membership.data.role!=='superadmin'||claims.aal!=='aal2')return res.status(403).json({error:'Superadministrateur avec double authentification requis.'});
   let body=req.body;if(typeof body==='string'){try{body=JSON.parse(body);}catch{return res.status(400).json({error:'Demande invalide.'});}}
   const email=typeof body?.email==='string'?body.email.trim().toLowerCase():'';
   const role=body?.role;
   if(email.length>254||!/^\S+@[^\s@]+\.[^\s@]+$/.test(email)||!['manager','editor','analyst'].includes(role))return res.status(400).json({error:'Adresse e-mail ou rôle invalide.'});
   const invited=await admin.auth.admin.inviteUserByEmail(email,{redirectTo:redirect.href});
   if(invited.error||!invited.data?.user)return res.status(409).json({error:'Invitation non envoyée. Le compte peut déjà exister ; vérifiez son accès avant de réessayer.'});
   // INSERT : ne réactive ni ne remplace les droits d’un compte déjà membre.
   const saved=await admin.from('koki_admin_members').insert({user_id:invited.data.user.id,role,enabled:true});
   if(saved.error)return res.status(503).json({error:'E-mail envoyé, mais accès non accordé. Contactez le responsable technique avant de réessayer.'});
   return res.status(200).json({message:'Invitation envoyée. Le destinataire pourra définir son mot de passe puis activer la double authentification.'});
  }catch{return res.status(503).json({error:'Invitation indisponible. Réessayez plus tard.'});}
 };
}
export default invitationHandler();
