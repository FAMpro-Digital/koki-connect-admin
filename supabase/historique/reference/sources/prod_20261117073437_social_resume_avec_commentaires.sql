do $t$
declare d text; n int;
begin
 d:=pg_get_functiondef('koki_social_private.summaries'::regproc);
 if position('''comments''' in d)>0 then raise exception 'Préflight : déjà appliqué';end if;
 n:=(length(d)-length(replace(d,$a$'liked',exists($a$,'')))/length($a$'liked',exists($a$);
 if n<>1 then raise exception 'Préflight : % occurrence(s)',n;end if;
 execute replace(d,$a$'liked',exists($a$,$b$'comments',(select count(*) from koki_social_private.comments k where k.content_id=c.id and not k.hidden),'liked',exists($b$);
end $t$;

