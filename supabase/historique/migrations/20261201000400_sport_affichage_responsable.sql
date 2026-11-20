-- Espace Clubs & Académies — 5 : l'affichage public d'un joueur est décidé par le responsable de l'académie.
-- Décision de Mourtada Fam (20/11/2026) : plus de circuit d'autorisation parentale dans l'application.
-- APPLIQUÉE EN PRODUCTION le 20/11/2026 (soir). Voir supabase/production/README.md.
--  * player_consents.mode accepte 'responsable' (décision du responsable, datée et attribuée : recueilli_par).
--  * koki_sport.handle / consent_save : plus d'obligation d'enregistrer un représentant légal ; la date
--    (current_date) et le mode ('responsable') sont fixés par le serveur. Le retrait reste immédiat.
-- Inchangé : rôle responsable exigé (permission manage), isolation par académie, filtre à la lecture publique.

begin;

do $$ begin
 if to_regclass('koki_sport.player_consents') is null then raise exception 'GARDE : migrations koki_sport 1 à 4 absentes'; end if;
 if (select md5(pg_get_functiondef('koki_sport.handle(text,jsonb)'::regprocedure)))<>'e6c5ec368e77974011f4f505953dc9bf' then
  raise exception 'GARDE : koki_sport.handle a changé depuis la référence'; end if;
 if (select pg_get_constraintdef(oid) from pg_constraint where conname='player_consents_mode_check' and conrelid='koki_sport.player_consents'::regclass)
    <>'CHECK (((mode IS NULL) OR (mode = ANY (ARRAY[''papier''::text, ''oral''::text, ''whatsapp''::text, ''autre''::text]))))' then
  raise exception 'GARDE : contrainte player_consents_mode_check inattendue'; end if;
end $$;

alter table koki_sport.player_consents drop constraint player_consents_mode_check;
alter table koki_sport.player_consents add constraint player_consents_mode_check
 check (mode is null or mode in ('papier','oral','whatsapp','autre','responsable'));

CREATE OR REPLACE FUNCTION koki_sport.handle(command text, input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 a uuid; club uuid; cat uuid; oldcat uuid; rid uuid; n integer; code text; h text; out jsonb; r text;
 c koki_sport.clubs; p koki_sport.players; s koki_sport.sessions; m koki_sport.matches; po koki_sport.posts; me koki_sport.media;
 co koki_sport.competitions; st koki_sport.staff; inv koki_sport.club_invitations; mb koki_sport.club_members; pc koki_sport.player_consents;
 g koki_sport.player_guardians; ca koki_sport.categories; x jsonb;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'Requête invalide ou trop volumineuse'; end if;
 a:=koki_sport.actor();

 if command='my_clubs' then
  perform koki_sport.keys(input,'{}');
  return coalesce((select jsonb_agg(koki_sport.club_json(c2)||jsonb_build_object('role',m2.role) order by c2.nom)
   from koki_sport.club_members m2 join koki_sport.clubs c2 on c2.id=m2.club_id where m2.user_id=a and m2.statut='actif' and c2.statut<>'Archivé'),'[]');

 elsif command='create_club' then
  perform koki_sport.keys(input,'{nom,type,discipline,localite_id,telephone,whatsapp,presentation}');
  if (select count(*) from koki_sport.club_members m2 join koki_sport.clubs c2 on c2.id=m2.club_id
      where m2.user_id=a and m2.role='responsable' and m2.statut='actif' and c2.statut<>'Archivé')>=3 then
   raise exception 'Trois académies au maximum par compte'; end if;
  h:=koki_sport.slugify(koki_sport.t(input,'nom'));
  if h='' then raise exception 'Nom invalide'; end if;
  n:=1; code:=h;
  while exists(select 1 from koki_sport.clubs where slug=code) loop n:=n+1; code:=left(h,66)||'-'||n; end loop;
  insert into koki_sport.clubs(nom,slug,type,discipline,localite_id,telephone,whatsapp,presentation,created_by)
  values(koki_sport.t(input,'nom'),code,koki_sport.t(input,'type','Académie'),koki_sport.t(input,'discipline','Football'),koki_sport.u(input,'localite_id',false),
   nullif(koki_sport.t(input,'telephone'),''),nullif(koki_sport.t(input,'whatsapp'),''),koki_sport.t(input,'presentation'),a) returning * into c;
  insert into koki_sport.club_members(club_id,user_id,role,invited_by) values(c.id,a,'responsable',a);
  return koki_sport.club_json(c)||jsonb_build_object('role','responsable');

 elsif command='accept_invitation' then
  perform koki_sport.keys(input,'{code}');
  perform pg_advisory_xact_lock(hashtextextended('sport-invite:'||a::text,0));
  if (select count(*) from koki_sport.invitation_attempts t where t.actor_id=a and t.created_at>now()-interval '15 minutes')>=5
   or (select count(*) from koki_sport.invitation_attempts t where t.actor_id=a and t.created_at>now()-interval '1 day')>=20 then
   raise exception 'Trop d’essais. Réessayez plus tard.'; end if;
  delete from koki_sport.invitation_attempts t where t.actor_id=a and t.created_at<now()-interval '2 days';
  insert into koki_sport.invitation_attempts(actor_id) values(a);
  h:=encode(extensions.digest(upper(regexp_replace(koki_sport.t(input,'code'),'[^A-Za-z0-9]','','g')),'sha256'),'hex');
  select * into inv from koki_sport.club_invitations i where i.code_hash=h for update;
  if inv.id is null or inv.statut<>'active' or inv.expires_at<now() then return jsonb_build_object('ok',false,'erreur','Code d’invitation invalide ou expiré'); end if;
  if not koki_sport.club_writable(inv.club_id) then raise exception 'Cette académie n’accepte pas de nouveaux membres pour le moment'; end if;
  select * into mb from koki_sport.club_members where club_id=inv.club_id and user_id=a;
  if mb.id is null then insert into koki_sport.club_members(club_id,user_id,role,invited_by) values(inv.club_id,a,inv.role,inv.created_by);
  else update koki_sport.club_members set role=case when mb.role='responsable' and mb.statut='actif' then 'responsable' else inv.role end, statut='actif' where id=mb.id; end if;
  if inv.staff_id is not null then
   update koki_sport.staff set user_id=null where club_id=inv.club_id and user_id=a and id<>inv.staff_id;
   update koki_sport.staff set user_id=a where id=inv.staff_id and club_id=inv.club_id;
  end if;
  update koki_sport.club_invitations set statut='utilisée', used_by=a where id=inv.id;
  select * into c from koki_sport.clubs where id=inv.club_id;
  return koki_sport.club_json(c)||jsonb_build_object('ok',true,'role',koki_sport.role_in(c.id));

 elsif command in ('follow','unfollow') then
  perform koki_sport.keys(input,'{club_id,notifications}');
  club:=koki_sport.u(input,'club_id');
  if command='unfollow' then delete from koki_sport.follows where user_id=a and club_id=club; return jsonb_build_object('suivi',false); end if;
  if not exists(select 1 from koki_sport.clubs where id=club and statut='Actif') then raise exception 'Académie introuvable'; end if;
  insert into koki_sport.follows(user_id,club_id,notifications) values(a,club,koki_sport.b(input,'notifications',true))
   on conflict(user_id,club_id) do update set notifications=excluded.notifications;
  return jsonb_build_object('suivi',true);

 elsif command='report' then
  perform koki_sport.keys(input,'{cible_type,cible_id,motif,details}');
  rid:=koki_sport.u(input,'cible_id');
  club:=case koki_sport.t(input,'cible_type')
   when 'club' then (select id from koki_sport.clubs where id=rid and statut='Actif')
   when 'post' then (select club_id from koki_sport.posts where id=rid and statut='publié')
   when 'media' then (select club_id from koki_sport.media where id=rid and koki_sport.media_public(id)) end;
  if club is null then raise exception 'Contenu introuvable'; end if;
  if (select count(*) from koki_sport.reports where reporter_id=a and created_at>now()-interval '1 hour')>=10 then raise exception 'Trop de signalements. Réessayez plus tard.'; end if;
  insert into koki_sport.reports(club_id,cible_type,cible_id,reporter_id,motif,details)
  values(club,koki_sport.t(input,'cible_type'),rid,a,koki_sport.t(input,'motif'),koki_sport.t(input,'details')) returning id into rid;
  return jsonb_build_object('id',rid);
 end if;

 if command like 'admin\_%' then
  return koki_sport.admin(command,input);
 end if;

 if command='club_get' then
  perform koki_sport.keys(input,'{club_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'read');
  select * into c from koki_sport.clubs where id=club; r:=koki_sport.role_in(club);
  return koki_sport.club_json(c)||jsonb_build_object('role',r,
   'categories_entraineur',to_jsonb(koki_sport.coach_cats(club)),
   'categories',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'nom',k.nom,'annee_min',k.annee_min,'annee_max',k.annee_max,'ordre',k.ordre,'statut',k.statut,'revision',k.revision,
      'joueurs',(select count(*) from koki_sport.players p2 where p2.categorie_id=k.id and p2.statut='actif')) order by k.ordre,k.nom) from koki_sport.categories k where k.club_id=club),'[]'),
   'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s2.id,'prenom',s2.prenom,'nom',s2.nom,'fonction',s2.fonction,'photo_path',s2.photo_path,'public',s2.public,'statut',s2.statut,'revision',s2.revision,
      'lie_a_un_compte',s2.user_id is not null,'telephone',case when r='responsable' then s2.telephone end,
      'categories',(select coalesce(jsonb_agg(sc.categorie_id),'[]') from koki_sport.staff_categories sc where sc.staff_id=s2.id)) order by s2.nom) from koki_sport.staff s2 where s2.club_id=club),'[]'),
   'membres',case when r='responsable' then coalesce((select jsonb_agg(jsonb_build_object('id',m2.id,'role',m2.role,'statut',m2.statut,'moi',m2.user_id=a,'revision',m2.revision,'depuis',m2.created_at)) from koki_sport.club_members m2 where m2.club_id=club),'[]') end,
   'invitations',case when r='responsable' then coalesce((select jsonb_agg(jsonb_build_object('id',i2.id,'role',i2.role,'expire',i2.expires_at,'statut',i2.statut)) from koki_sport.club_invitations i2 where i2.club_id=club and i2.statut='active' and i2.expires_at>now()),'[]') end,
   'compteurs',jsonb_build_object('joueurs',(select count(*) from koki_sport.players p2 where p2.club_id=club and p2.statut='actif'),
      'abonnes',(select count(*) from koki_sport.follows f where f.club_id=club),
      'publications',(select count(*) from koki_sport.posts p3 where p3.club_id=club and p3.statut='publié')),
   'prochaines_seances',coalesce((select jsonb_agg(to_jsonb(s3) order by s3.debut) from (select * from koki_sport.sessions s4 where s4.club_id=club and s4.debut>=now()-interval '3 hours' and s4.statut<>'annulée' order by s4.debut limit 10) s3),'[]'),
   'matchs',coalesce((select jsonb_agg(koki_sport.match_json(m3) order by m3.date_match desc) from (select * from koki_sport.matches m4 where m4.club_id=club order by m4.date_match desc limit 30) m3),'[]'),
   'competitions',coalesce((select jsonb_agg(to_jsonb(c3)||jsonb_build_object('equipes',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'nom',t.nom,'is_self',t.is_self) order by t.nom),'[]') from koki_sport.competition_teams t where t.competition_id=c3.id)) order by c3.created_at desc) from koki_sport.competitions c3 where c3.club_id=club),'[]'),
   'publications',coalesce((select jsonb_agg(to_jsonb(p5)-'masque_par'-'created_by' order by p5.created_at desc) from (select * from koki_sport.posts p6 where p6.club_id=club order by p6.created_at desc limit 30) p5),'[]'));

 elsif command='club_update' then
  perform koki_sport.keys(input,'{club_id,revision,nom,type,discipline,presentation,historique,activites,localite_id,adresse,latitude,longitude,telephone,whatsapp,logo_path,couleurs}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'profile');
  select * into c from koki_sport.clubs where id=club for update; perform koki_sport.check_revision(c.revision,input);
  if input ? 'logo_path' and nullif(koki_sport.t(input,'logo_path'),'') is not null and koki_sport.folder_club(koki_sport.t(input,'logo_path')) is distinct from club then raise exception 'Image hors du dossier de l’académie'; end if;
  update koki_sport.clubs set
   nom=case when input ? 'nom' then koki_sport.t(input,'nom') else nom end,
   type=case when input ? 'type' then koki_sport.t(input,'type') else type end,
   discipline=case when input ? 'discipline' then koki_sport.t(input,'discipline') else discipline end,
   presentation=case when input ? 'presentation' then koki_sport.t(input,'presentation') else presentation end,
   historique=case when input ? 'historique' then koki_sport.t(input,'historique') else historique end,
   activites=case when input ? 'activites' then koki_sport.t(input,'activites') else activites end,
   localite_id=case when input ? 'localite_id' then koki_sport.u(input,'localite_id',false) else localite_id end,
   adresse=case when input ? 'adresse' then koki_sport.t(input,'adresse') else adresse end,
   latitude=case when input ? 'latitude' then (input->>'latitude')::numeric else latitude end,
   longitude=case when input ? 'longitude' then (input->>'longitude')::numeric else longitude end,
   telephone=case when input ? 'telephone' then nullif(koki_sport.t(input,'telephone'),'') else telephone end,
   whatsapp=case when input ? 'whatsapp' then nullif(koki_sport.t(input,'whatsapp'),'') else whatsapp end,
   logo_path=case when input ? 'logo_path' then nullif(koki_sport.t(input,'logo_path'),'') else logo_path end,
   couleurs=case when input ? 'couleurs' then array(select lower(jsonb_array_elements_text(input->'couleurs'))) else couleurs end
  where id=club returning * into c;
  return koki_sport.club_json(c);

 elsif command='invite' then
  perform koki_sport.keys(input,'{club_id,role,staff_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'manage');
  return koki_sport.new_invitation(club,koki_sport.t(input,'role'),koki_sport.u(input,'staff_id',false),a);

 elsif command='invitation_cancel' then
  perform koki_sport.keys(input,'{id}');
  select * into inv from koki_sport.club_invitations where id=koki_sport.u(input,'id') for update;
  if inv.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(inv.club_id,'manage');
  update koki_sport.club_invitations set statut='annulée' where id=inv.id and statut='active';
  return jsonb_build_object('id',inv.id,'statut','annulée');

 elsif command='member_update' then
  perform koki_sport.keys(input,'{id,revision,role,statut}');
  select * into mb from koki_sport.club_members where id=koki_sport.u(input,'id') for update;
  if mb.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(mb.club_id,'manage'); perform koki_sport.check_revision(mb.revision,input);
  update koki_sport.club_members set role=coalesce(nullif(koki_sport.t(input,'role'),''),role), statut=coalesce(nullif(koki_sport.t(input,'statut'),''),statut) where id=mb.id returning * into mb;
  if mb.statut='retiré' then update koki_sport.staff set user_id=null where club_id=mb.club_id and user_id=mb.user_id; end if;
  return jsonb_build_object('id',mb.id,'role',mb.role,'statut',mb.statut,'revision',mb.revision);

 elsif command='category_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,nom,annee_min,annee_max,ordre,statut}');
  rid:=koki_sport.u(input,'id',false);
  if rid is null then
   club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'manage');
   if (select count(*) from koki_sport.categories where club_id=club)>=40 then raise exception '40 catégories au maximum'; end if;
   insert into koki_sport.categories(club_id,nom,annee_min,annee_max,ordre) values(club,koki_sport.t(input,'nom'),koki_sport.i(input,'annee_min'),koki_sport.i(input,'annee_max'),coalesce(koki_sport.i(input,'ordre'),0)) returning * into ca;
  else
   select * into ca from koki_sport.categories where id=rid for update;
   if ca.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(ca.club_id,'manage'); perform koki_sport.check_revision(ca.revision,input);
   if koki_sport.t(input,'statut',ca.statut)='archivée' and exists(select 1 from koki_sport.players where categorie_id=ca.id and statut='actif') then raise exception 'Déplacez d’abord les joueurs actifs de cette catégorie'; end if;
   update koki_sport.categories set nom=koki_sport.t(input,'nom',nom), annee_min=koki_sport.i(input,'annee_min'), annee_max=koki_sport.i(input,'annee_max'),
    ordre=coalesce(koki_sport.i(input,'ordre'),ordre), statut=koki_sport.t(input,'statut',statut) where id=rid returning * into ca;
  end if;
  return to_jsonb(ca);

 elsif command='staff_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,prenom,nom,fonction,telephone,photo_path,public,statut,categories}');
  rid:=koki_sport.u(input,'id',false);
  if rid is null then club:=koki_sport.u(input,'club_id'); else select club_id into club from koki_sport.staff where id=rid; end if;
  if club is null then perform koki_sport.deny(); end if; perform koki_sport.require(club,'manage');
  if nullif(koki_sport.t(input,'photo_path'),'') is not null and koki_sport.folder_club(koki_sport.t(input,'photo_path')) is distinct from club then raise exception 'Image hors du dossier de l’académie'; end if;
  if rid is null then
   insert into koki_sport.staff(club_id,prenom,nom,fonction,telephone,photo_path,public) values(club,koki_sport.t(input,'prenom'),koki_sport.t(input,'nom'),koki_sport.t(input,'fonction'),
    nullif(koki_sport.t(input,'telephone'),''),nullif(koki_sport.t(input,'photo_path'),''),koki_sport.b(input,'public')) returning * into st;
  else
   select * into st from koki_sport.staff where id=rid for update; perform koki_sport.check_revision(st.revision,input);
   update koki_sport.staff set prenom=koki_sport.t(input,'prenom',prenom), nom=koki_sport.t(input,'nom',nom), fonction=koki_sport.t(input,'fonction',fonction),
    telephone=case when input ? 'telephone' then nullif(koki_sport.t(input,'telephone'),'') else telephone end,
    photo_path=case when input ? 'photo_path' then nullif(koki_sport.t(input,'photo_path'),'') else photo_path end,
    public=koki_sport.b(input,'public',public), statut=koki_sport.t(input,'statut',statut),
    user_id=case when koki_sport.t(input,'statut',statut)='archivé' then null else user_id end where id=rid returning * into st;
  end if;
  if input ? 'categories' then
   delete from koki_sport.staff_categories where staff_id=st.id;
   insert into koki_sport.staff_categories(club_id,staff_id,categorie_id) select club,st.id,x2::uuid from jsonb_array_elements_text(input->'categories') x2;
  end if;
  return to_jsonb(st)-'user_id'||jsonb_build_object('categories',(select coalesce(jsonb_agg(categorie_id),'[]') from koki_sport.staff_categories where staff_id=st.id));

 elsif command='players_list' then
  perform koki_sport.keys(input,'{club_id,categorie_id,archives}');
  club:=koki_sport.u(input,'club_id'); cat:=koki_sport.u(input,'categorie_id',false); perform koki_sport.require(club,'read');
  r:=koki_sport.role_in(club);
  if r not in ('responsable','entraineur') then perform koki_sport.deny(); end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',p2.id,'categorie_id',p2.categorie_id,'prenom',p2.prenom,'nom',p2.nom,'annee_naissance',p2.annee_naissance,'poste',p2.poste,'numero',p2.numero,
     'photo_path',p2.photo_path,'statut',p2.statut,'revision',p2.revision,
     'consentement',(select jsonb_build_object('nom_public',pc2.nom_public,'photo',pc2.photo,'video',pc2.video,'stats',pc2.stats,'statut',pc2.statut) from koki_sport.player_consents pc2 where pc2.player_id=p2.id))
    order by p2.nom,p2.prenom)
   from koki_sport.players p2 where p2.club_id=club and (cat is null or p2.categorie_id=cat) and (p2.statut='actif' or koki_sport.b(input,'archives'))
    and (r='responsable' or p2.categorie_id=any(koki_sport.coach_cats(club)))),'[]');

 elsif command='player_get' then
  perform koki_sport.keys(input,'{id}');
  select * into p from koki_sport.players where id=koki_sport.u(input,'id');
  if p.id is null or not koki_sport.can(p.club_id,'players',p.categorie_id) then perform koki_sport.deny(); end if;
  return to_jsonb(p)||jsonb_build_object(
   'representants',(select coalesce(jsonb_agg(to_jsonb(g2) order by g2.created_at),'[]') from koki_sport.player_guardians g2 where g2.player_id=p.id and g2.statut='actif'),
   'consentement',(select to_jsonb(pc2)-'recueilli_par' from koki_sport.player_consents pc2 where pc2.player_id=p.id),
   'presences',(select jsonb_build_object('seances',count(*),'presents',count(*) filter (where present)) from koki_sport.attendance at2 where at2.player_id=p.id),
   'statistiques',(select jsonb_object_agg(type,n2) from (select type,count(*) n2 from koki_sport.match_events e where e.player_id=p.id group by type) z));

 elsif command='player_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,categorie_id,prenom,nom,annee_naissance,poste,numero,photo_path}');
  rid:=koki_sport.u(input,'id',false); cat:=koki_sport.u(input,'categorie_id');
  if rid is null then
   club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'players',cat);
   if (select count(*) from koki_sport.players where club_id=club and statut='actif')>=500 then raise exception '500 joueurs actifs au maximum'; end if;
  else
   select * into p from koki_sport.players where id=rid for update;
   if p.id is null then perform koki_sport.deny(); end if; club:=p.club_id;
   perform koki_sport.require(club,'players',p.categorie_id); perform koki_sport.require(club,'players',cat); perform koki_sport.check_revision(p.revision,input);
  end if;
  if not exists(select 1 from koki_sport.categories where id=cat and club_id=club and statut='active') then raise exception 'Catégorie invalide'; end if;
  if nullif(koki_sport.t(input,'photo_path'),'') is not null and koki_sport.folder_club(koki_sport.t(input,'photo_path')) is distinct from club then raise exception 'Image hors du dossier de l’académie'; end if;
  if rid is null then
   insert into koki_sport.players(club_id,categorie_id,prenom,nom,annee_naissance,poste,numero,photo_path) values(club,cat,koki_sport.t(input,'prenom'),koki_sport.t(input,'nom'),
    koki_sport.i(input,'annee_naissance'),koki_sport.t(input,'poste'),koki_sport.i(input,'numero'),nullif(koki_sport.t(input,'photo_path'),'')) returning * into p;
   insert into koki_sport.player_consents(club_id,player_id) values(club,p.id);
  else
   update koki_sport.players set categorie_id=cat, prenom=koki_sport.t(input,'prenom',prenom), nom=koki_sport.t(input,'nom',nom),
    annee_naissance=case when input ? 'annee_naissance' then koki_sport.i(input,'annee_naissance') else annee_naissance end,
    poste=koki_sport.t(input,'poste',poste), numero=case when input ? 'numero' then koki_sport.i(input,'numero') else numero end,
    photo_path=case when input ? 'photo_path' then nullif(koki_sport.t(input,'photo_path'),'') else photo_path end where id=rid returning * into p;
  end if;
  return to_jsonb(p);

 elsif command='player_archive' then
  perform koki_sport.keys(input,'{id,revision,restaurer}');
  select * into p from koki_sport.players where id=koki_sport.u(input,'id') for update;
  if p.id is null then perform koki_sport.deny(); end if;
  perform koki_sport.require(p.club_id,'players',p.categorie_id); perform koki_sport.check_revision(p.revision,input);
  if koki_sport.b(input,'restaurer') then update koki_sport.players set statut='actif', sorti_le=null where id=p.id returning * into p;
  else update koki_sport.players set statut='archivé', sorti_le=current_date where id=p.id returning * into p; end if;
  return to_jsonb(p);

 elsif command='guardian_save' then
  perform koki_sport.keys(input,'{player_id,id,revision,nom,lien,telephone,statut}');
  rid:=koki_sport.u(input,'id',false);
  if rid is null then select * into p from koki_sport.players where id=koki_sport.u(input,'player_id');
  else select * into g from koki_sport.player_guardians where id=rid for update; select * into p from koki_sport.players where id=g.player_id; end if;
  if p.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(p.club_id,'manage');
  if rid is null then
   if (select count(*) from koki_sport.player_guardians where player_id=p.id and statut='actif')>=3 then raise exception 'Trois représentants au maximum'; end if;
   insert into koki_sport.player_guardians(club_id,player_id,nom,lien,telephone) values(p.club_id,p.id,koki_sport.t(input,'nom'),koki_sport.t(input,'lien'),nullif(koki_sport.t(input,'telephone'),'')) returning * into g;
  else
   perform koki_sport.check_revision(g.revision,input);
   update koki_sport.player_guardians set nom=koki_sport.t(input,'nom',nom), lien=koki_sport.t(input,'lien',lien),
    telephone=case when input ? 'telephone' then nullif(koki_sport.t(input,'telephone'),'') else telephone end, statut=koki_sport.t(input,'statut',statut) where id=rid returning * into g;
  end if;
  return to_jsonb(g);

 elsif command in ('consent_save','consent_revoke') then
  perform koki_sport.keys(input,'{player_id,revision,nom_public,photo,video,stats,recueilli_le,mode}');
  select * into pc from koki_sport.player_consents where player_id=koki_sport.u(input,'player_id') for update;
  if pc.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(pc.club_id,'manage'); perform koki_sport.check_revision(pc.revision,input);
  if command='consent_revoke' then
   update koki_sport.player_consents set statut='retiré' where id=pc.id returning * into pc;
  else
   if (koki_sport.b(input,'photo') or koki_sport.b(input,'video') or koki_sport.b(input,'stats')) and koki_sport.t(input,'nom_public','aucun')='aucun' and koki_sport.b(input,'stats') then
    raise exception 'Les statistiques publiques exigent un nom public'; end if;
   update koki_sport.player_consents set statut='actif', retire_le=null, nom_public=koki_sport.t(input,'nom_public','aucun'),
    photo=koki_sport.b(input,'photo'), video=koki_sport.b(input,'video'), stats=koki_sport.b(input,'stats'),
    recueilli_le=case when koki_sport.t(input,'nom_public','aucun')<>'aucun' or koki_sport.b(input,'photo') or koki_sport.b(input,'video') or koki_sport.b(input,'stats') then current_date end,
    mode=case when koki_sport.t(input,'nom_public','aucun')<>'aucun' or koki_sport.b(input,'photo') or koki_sport.b(input,'video') or koki_sport.b(input,'stats') then 'responsable' end,
    recueilli_par=a where id=pc.id returning * into pc;
  end if;
  return to_jsonb(pc)-'recueilli_par';

 elsif command='session_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,categorie_id,debut,fin,lieu,theme,statut}');
  rid:=koki_sport.u(input,'id',false); cat:=koki_sport.u(input,'categorie_id');
  if rid is null then club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'sport',cat);
  else select * into s from koki_sport.sessions where id=rid for update; if s.id is null then perform koki_sport.deny(); end if;
   club:=s.club_id; perform koki_sport.require(club,'sport',s.categorie_id); perform koki_sport.require(club,'sport',cat); perform koki_sport.check_revision(s.revision,input); end if;
  if rid is null then
   insert into koki_sport.sessions(club_id,categorie_id,debut,fin,lieu,theme) values(club,cat,koki_sport.ts(input,'debut'),koki_sport.ts(input,'fin'),koki_sport.t(input,'lieu'),koki_sport.t(input,'theme')) returning * into s;
  else
   update koki_sport.sessions set categorie_id=cat, debut=koki_sport.ts(input,'debut'), fin=koki_sport.ts(input,'fin'), lieu=koki_sport.t(input,'lieu',lieu), theme=koki_sport.t(input,'theme',theme),
    statut=koki_sport.t(input,'statut',statut) where id=rid returning * into s;
  end if;
  return to_jsonb(s);

 elsif command='sessions_list' then
  perform koki_sport.keys(input,'{club_id,du,au}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'read');
  return coalesce((select jsonb_agg(to_jsonb(s2)||jsonb_build_object('categorie',(select nom from koki_sport.categories where id=s2.categorie_id)) order by s2.debut)
   from koki_sport.sessions s2 where s2.club_id=club and s2.debut>=coalesce(koki_sport.ts(input,'du',false),now()-interval '30 days') and s2.debut<=coalesce(koki_sport.ts(input,'au',false),now()+interval '60 days')),'[]');

 elsif command='attendance_save' then
  perform koki_sport.keys(input,'{session_id,presences}');
  select * into s from koki_sport.sessions where id=koki_sport.u(input,'session_id');
  if s.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(s.club_id,'sport',s.categorie_id);
  if jsonb_typeof(input->'presences')<>'array' or jsonb_array_length(input->'presences')>200 then raise exception 'Liste de présences invalide'; end if;
  insert into koki_sport.attendance(club_id,session_id,player_id,present)
   select s.club_id,s.id,(e->>'player_id')::uuid,(e->>'present')::boolean from jsonb_array_elements(input->'presences') e
   on conflict(session_id,player_id) do update set present=excluded.present, updated_at=now();
  return jsonb_build_object('session_id',s.id,'enregistrees',jsonb_array_length(input->'presences'));

 elsif command='attendance_get' then
  perform koki_sport.keys(input,'{session_id}');
  select * into s from koki_sport.sessions where id=koki_sport.u(input,'session_id');
  if s.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(s.club_id,'sport',s.categorie_id);
  return coalesce((select jsonb_agg(jsonb_build_object('player_id',at2.player_id,'present',at2.present)) from koki_sport.attendance at2 where at2.session_id=s.id),'[]');

 elsif command='competition_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,nom,saison,type,categorie_id,organisateur,statut}');
  rid:=koki_sport.u(input,'id',false); cat:=koki_sport.u(input,'categorie_id',false);
  if rid is null then club:=koki_sport.u(input,'club_id');
  else select * into co from koki_sport.competitions where id=rid for update; if co.id is null then perform koki_sport.deny(); end if; club:=co.club_id;
   if co.categorie_id is null then perform koki_sport.require(club,'manage'); else perform koki_sport.require(club,'sport',co.categorie_id); end if;
   perform koki_sport.check_revision(co.revision,input); end if;
  if cat is null then perform koki_sport.require(club,'manage'); else perform koki_sport.require(club,'sport',cat); end if;
  if rid is null then
   insert into koki_sport.competitions(club_id,nom,saison,type,categorie_id,organisateur) values(club,koki_sport.t(input,'nom'),koki_sport.t(input,'saison'),koki_sport.t(input,'type','Championnat'),cat,koki_sport.t(input,'organisateur')) returning * into co;
   insert into koki_sport.competition_teams(club_id,competition_id,nom,is_self) select club,co.id,c2.nom,true from koki_sport.clubs c2 where c2.id=club;
  else
   update koki_sport.competitions set nom=koki_sport.t(input,'nom',nom), saison=koki_sport.t(input,'saison',saison), type=koki_sport.t(input,'type',type), categorie_id=cat,
    organisateur=koki_sport.t(input,'organisateur',organisateur), statut=koki_sport.t(input,'statut',statut) where id=rid returning * into co;
  end if;
  return to_jsonb(co);

 elsif command in ('team_add','team_delete') then
  perform koki_sport.keys(input,'{competition_id,id,nom}');
  if command='team_add' then select * into co from koki_sport.competitions where id=koki_sport.u(input,'competition_id');
  else select co2.* into co from koki_sport.competitions co2 join koki_sport.competition_teams t on t.competition_id=co2.id where t.id=koki_sport.u(input,'id'); end if;
  if co.id is null then perform koki_sport.deny(); end if;
  if co.categorie_id is null then perform koki_sport.require(co.club_id,'manage'); else perform koki_sport.require(co.club_id,'sport',co.categorie_id); end if;
  if command='team_add' then
   if (select count(*) from koki_sport.competition_teams where competition_id=co.id)>=40 then raise exception '40 équipes au maximum'; end if;
   insert into koki_sport.competition_teams(club_id,competition_id,nom) values(co.club_id,co.id,koki_sport.t(input,'nom')) returning id into rid;
   return jsonb_build_object('id',rid,'nom',koki_sport.t(input,'nom'));
  end if;
  if exists(select 1 from koki_sport.competition_teams where id=koki_sport.u(input,'id') and is_self) then raise exception 'L’équipe de l’académie ne peut pas être retirée'; end if;
  delete from koki_sport.competition_teams where id=koki_sport.u(input,'id') and competition_id=co.id;
  return jsonb_build_object('id',koki_sport.u(input,'id'),'supprime',true);

 elsif command='match_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,categorie_id,competition_id,home_team_id,away_team_id,adversaire,a_domicile,date_match,lieu,statut,score_domicile,score_exterieur,journee}');
  rid:=koki_sport.u(input,'id',false); cat:=koki_sport.u(input,'categorie_id');
  if rid is null then club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'sport',cat);
  else select * into m from koki_sport.matches where id=rid for update; if m.id is null then perform koki_sport.deny(); end if;
   club:=m.club_id; perform koki_sport.require(club,'sport',m.categorie_id); perform koki_sport.require(club,'sport',cat); perform koki_sport.check_revision(m.revision,input); end if;
  if rid is null then
   insert into koki_sport.matches(club_id,categorie_id,competition_id,home_team_id,away_team_id,adversaire,a_domicile,date_match,lieu,statut,score_home,score_away,journee)
   values(club,cat,koki_sport.u(input,'competition_id',false),koki_sport.u(input,'home_team_id',false),koki_sport.u(input,'away_team_id',false),
    nullif(koki_sport.t(input,'adversaire'),''),case when input ? 'a_domicile' and input->'a_domicile'<>'null'::jsonb then koki_sport.b(input,'a_domicile') end,
    koki_sport.ts(input,'date_match'),koki_sport.t(input,'lieu'),koki_sport.t(input,'statut','À venir'),koki_sport.i(input,'score_domicile'),koki_sport.i(input,'score_exterieur'),koki_sport.t(input,'journee')) returning * into m;
  else
   update koki_sport.matches set categorie_id=cat, competition_id=koki_sport.u(input,'competition_id',false), home_team_id=koki_sport.u(input,'home_team_id',false), away_team_id=koki_sport.u(input,'away_team_id',false),
    adversaire=nullif(koki_sport.t(input,'adversaire'),''), a_domicile=case when input ? 'a_domicile' and input->'a_domicile'<>'null'::jsonb then koki_sport.b(input,'a_domicile') end,
    date_match=koki_sport.ts(input,'date_match'), lieu=koki_sport.t(input,'lieu',lieu), statut=koki_sport.t(input,'statut',statut),
    score_home=koki_sport.i(input,'score_domicile'), score_away=koki_sport.i(input,'score_exterieur'), journee=koki_sport.t(input,'journee',journee) where id=rid returning * into m;
  end if;
  return koki_sport.match_json(m);

 elsif command in ('match_event_add','match_event_delete') then
  perform koki_sport.keys(input,'{match_id,id,player_id,type,minute}');
  if command='match_event_add' then select * into m from koki_sport.matches where id=koki_sport.u(input,'match_id');
  else select m2.* into m from koki_sport.matches m2 join koki_sport.match_events e on e.match_id=m2.id where e.id=koki_sport.u(input,'id'); end if;
  if m.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(m.club_id,'sport',m.categorie_id);
  if command='match_event_delete' then delete from koki_sport.match_events where id=koki_sport.u(input,'id'); return jsonb_build_object('supprime',true); end if;
  insert into koki_sport.match_events(club_id,match_id,player_id,type,minute) values(m.club_id,m.id,koki_sport.u(input,'player_id'),koki_sport.t(input,'type'),koki_sport.i(input,'minute')) returning id into rid;
  return jsonb_build_object('id',rid);

 elsif command='standings' then
  perform koki_sport.keys(input,'{competition_id}');
  select * into co from koki_sport.competitions where id=koki_sport.u(input,'competition_id');
  if co.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(co.club_id,'read');
  return koki_sport.standings(co.id);

 elsif command='post_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,type,titre,texte,evenement,lieu}');
  rid:=koki_sport.u(input,'id',false);
  if rid is null then club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'media');
   insert into koki_sport.posts(club_id,type,titre,texte,evenement,lieu,created_by) values(club,koki_sport.t(input,'type','Actualité'),koki_sport.t(input,'titre'),koki_sport.t(input,'texte'),
    koki_sport.ts(input,'evenement',false),koki_sport.t(input,'lieu'),a) returning * into po;
  else select * into po from koki_sport.posts where id=rid for update; if po.id is null then perform koki_sport.deny(); end if;
   perform koki_sport.require(po.club_id,'media'); perform koki_sport.check_revision(po.revision,input);
   if po.statut='masqué' then raise exception 'Publication masquée par la modération : contactez FAMpro Digital'; end if;
   update koki_sport.posts set type=koki_sport.t(input,'type',type), titre=koki_sport.t(input,'titre',titre), texte=koki_sport.t(input,'texte',texte),
    evenement=case when input ? 'evenement' then koki_sport.ts(input,'evenement',false) else evenement end, lieu=koki_sport.t(input,'lieu',lieu) where id=rid returning * into po;
  end if;
  return to_jsonb(po)-'masque_par'-'created_by';

 elsif command in ('post_publish','post_relay') then
  perform koki_sport.keys(input,'{id,revision,publier,publication}');
  select * into po from koki_sport.posts where id=koki_sport.u(input,'id') for update;
  if po.id is null then perform koki_sport.deny(); end if; perform koki_sport.check_revision(po.revision,input);
  if po.statut='masqué' then raise exception 'Publication masquée par la modération : contactez FAMpro Digital'; end if;
  if command='post_relay' then
   perform koki_sport.require(po.club_id,'publish');
   if po.statut<>'publié' then raise exception 'Publiez d’abord cette actualité'; end if;
   update koki_sport.posts set relais='demandé' where id=po.id and relais in ('aucun','refusé') returning * into po;
  elsif koki_sport.b(input,'publier',true) then
   perform koki_sport.require(po.club_id,'publish');
   update koki_sport.posts set statut='publié', publication=coalesce(koki_sport.ts(input,'publication',false),now()) where id=po.id returning * into po;
  else
   perform koki_sport.require(po.club_id,'media');
   update koki_sport.posts set statut='brouillon', publication=null where id=po.id returning * into po;
  end if;
  return to_jsonb(po)-'masque_par'-'created_by';

 elsif command='tagging_list' then
  perform koki_sport.keys(input,'{club_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'media');
  return coalesce((select jsonb_agg(jsonb_build_object('id',p2.id,'nom',p2.prenom||' '||left(p2.nom,1)||'.','categorie',k.nom,
     'photo',coalesce(pc2.statut='actif' and pc2.photo,false),'video',coalesce(pc2.statut='actif' and pc2.video,false)) order by k.ordre,p2.prenom)
   from koki_sport.players p2 join koki_sport.categories k on k.id=p2.categorie_id left join koki_sport.player_consents pc2 on pc2.player_id=p2.id
   where p2.club_id=club and p2.statut='actif'),'[]');

 elsif command='media_add' then
  perform koki_sport.keys(input,'{club_id,post_id,type,storage_path,youtube_id,legende,contient_mineurs,joueurs}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'media');
  if input->'contient_mineurs' is null or jsonb_typeof(input->'contient_mineurs')<>'boolean' then raise exception 'Indiquez si des mineurs sont reconnaissables sur ce média'; end if;
  if koki_sport.b(input,'contient_mineurs') and coalesce(jsonb_array_length(input->'joueurs'),0)=0 then raise exception 'Désignez les joueurs reconnaissables : sans eux, le média restera privé'; end if;
  if (select count(*) from koki_sport.media where club_id=club)>=2000 then raise exception 'Limite de médias atteinte'; end if;
  insert into koki_sport.media(club_id,post_id,type,storage_path,youtube_id,legende,contient_mineurs,created_by)
  values(club,koki_sport.u(input,'post_id',false),koki_sport.t(input,'type'),nullif(koki_sport.t(input,'storage_path'),''),nullif(koki_sport.t(input,'youtube_id'),''),koki_sport.t(input,'legende'),
   koki_sport.b(input,'contient_mineurs'),a) returning * into me;
  if jsonb_typeof(input->'joueurs')='array' then
   insert into koki_sport.media_players(club_id,media_id,player_id) select club,me.id,x2::uuid from jsonb_array_elements_text(input->'joueurs') x2 on conflict do nothing;
  end if;
  return to_jsonb(me)-'created_by'||jsonb_build_object('public',koki_sport.media_public(me.id));

 elsif command in ('media_hide','media_delete') then
  perform koki_sport.keys(input,'{id,motif}');
  select * into me from koki_sport.media where id=koki_sport.u(input,'id') for update;
  if me.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(me.club_id,'media');
  if command='media_delete' then delete from koki_sport.media where id=me.id; return jsonb_build_object('id',me.id,'supprime',true,'storage_path',me.storage_path); end if;
  update koki_sport.media set statut='masqué', motif=nullif(koki_sport.t(input,'motif'),'') where id=me.id returning * into me;
  return to_jsonb(me)-'created_by';

 elsif command='media_list' then
  perform koki_sport.keys(input,'{club_id,post_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'read');
  return coalesce((select jsonb_agg(to_jsonb(m2)-'created_by'||jsonb_build_object('public',koki_sport.media_public(m2.id),
     'joueurs',(select coalesce(jsonb_agg(mp.player_id),'[]') from koki_sport.media_players mp where mp.media_id=m2.id)) order by m2.created_at desc)
   from koki_sport.media m2 where m2.club_id=club and (koki_sport.u(input,'post_id',false) is null or m2.post_id=koki_sport.u(input,'post_id',false))),'[]');

 elsif command='audit_list' then
  perform koki_sport.keys(input,'{club_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'manage');
  return coalesce((select jsonb_agg(jsonb_build_object('operation',au.operation,'objet',au.table_name,'statut',au.details->>'statut','revision',au.details->'revision','date',au.created_at,
     'par_moi',au.actor_id=a) order by au.id desc) from (select * from public.koki_audit au2 where au2.record_id in (
     select id from koki_sport.clubs where id=club union all select id from koki_sport.club_members where club_id=club union all select id from koki_sport.categories where club_id=club
     union all select id from koki_sport.staff where club_id=club union all select id from koki_sport.players where club_id=club union all select id from koki_sport.player_consents where club_id=club
     union all select id from koki_sport.sessions where club_id=club union all select id from koki_sport.matches where club_id=club union all select id from koki_sport.posts where club_id=club
     union all select id from koki_sport.media where club_id=club) order by au2.id desc limit 100) au),'[]');
 end if;

 raise exception 'Commande inconnue';
end $function$;

commit;
