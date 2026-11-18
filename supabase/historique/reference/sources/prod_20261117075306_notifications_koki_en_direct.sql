do $t$
declare d text; n int;
begin
 d:=pg_get_functiondef('koki_private.notify_contents'::regproc);
 if position('Décès et cérémonies' in d)>0 then raise exception 'Préflight : déjà appliqué';end if;
 n:=(length(d)-length(replace(d,$a$where c.une or (i.actif and$a$,'')))/length($a$where c.une or (i.actif and$a$);
 if n<>1 then raise exception 'Préflight : % occurrence(s)',n;end if;
 execute replace(d,$a$where c.une or (i.actif and$a$,$b$where c.une or (c.type='Annonces' and c.categorie in ('Décès et cérémonies','Coupure eau/électricité','Avis important')) or (c.type='Sports & ASC' and c.categorie='Résultat') or (i.actif and$b$);
end $t$;