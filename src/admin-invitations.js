export function renderAdminInvitations(host,{account,db,guard,n,field,formPanel}) {
 if(account?.role!=='superadmin')return;
 const section=n('section');section.className='panel';section.append(n('h2','Inviter un administrateur'),n('p','Le destinataire recevra un lien pour définir son mot de passe et configurer sa double authentification.'));
 const form=formPanel(),fields={};field(form,fields,'invite-email','Adresse e-mail','email',null,'',true);
 const roles={manager:'Gestionnaire — commerces et transport',editor:'Éditeur — contenus',analyst:'Lecteur — consultation'};
 const role=field(form,fields,'invite-role','Accès autorisé','text',Object.keys(roles),'manager',true);for(const option of role.options)option.textContent=roles[option.value];
 const send=n('button','Envoyer l’invitation');send.type='submit';send.className='primary';const status=n('p');status.setAttribute('role','status');form.append(send);section.append(form,status);host.append(section);
 form.onsubmit=async event=>{event.preventDefault();if(send.disabled||!form.reportValidity())return;send.disabled=true;status.textContent='Envoi de l’invitation…';try{
  const caller=await guard();if(caller.role!=='superadmin')throw Error('Accès réservé au superadministrateur.');
  const {data,error}=await db.auth.getSession();if(error||!data?.session)throw Error('Reconnectez-vous avant de réessayer.');
  const response=await fetch('/api/invite-admin',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+data.session.access_token},body:JSON.stringify({email:fields['invite-email'].value.trim(),role:role.value})});
  const result=await response.json();if(!response.ok)throw Error(result.error||'Invitation non envoyée.');status.textContent=result.message;fields['invite-email'].value='';
 }catch(error){status.textContent=error.message||'Invitation indisponible.';}finally{send.disabled=false;}};
}
