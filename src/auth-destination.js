export function authDestination(href){
 const u=new URL(href),hash=new URLSearchParams(u.hash.slice(1));
 const type=hash.get('type')||u.searchParams.get('type')||u.searchParams.get('action');
 return {onboarding:['invite','recovery'].includes(type),error:hash.has('error')||hash.has('error_code')||u.searchParams.has('error')||u.searchParams.has('error_code')};
}
export function recoveryURL(href){const u=new URL(href);u.hash='';u.search='';u.searchParams.set('action','recovery');return u.href;}
