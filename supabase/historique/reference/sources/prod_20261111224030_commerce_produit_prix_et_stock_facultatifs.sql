do $t$
declare d text; pairs text[][]; i int; n int;
begin
 d:=pg_get_functiondef('koki_private.commerce_business'::regproc);
 pairs:=array[
  [$a$if input->'price' is null or input->'price'='null'::jsonb then raise exception 'Prix produit obligatoire';end if;
   price:=koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide');stock:=koki_private.commerce_int(input,'stock',1000000,'Stock invalide');$a$,
   $b$price:=case when input ? 'price' and input->'price'<>'null'::jsonb then koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide') end;stock:=case when input ? 'stock' and input->'stock'<>'null'::jsonb then koki_private.commerce_int(input,'stock',1000000,'Stock invalide') end;$b$],
  [$a$if old_price<=price then raise exception 'L’ancien prix doit être supérieur au prix actuel';end if;end if;
   data:=data||jsonb_strip_nulls(jsonb_build_object('prix',price,'stock',stock,'ancien_prix',old_price));$a$,
   $b$if price is null or old_price<=price then raise exception 'L’ancien prix doit être supérieur au prix actuel';end if;end if;
   data:=data||jsonb_strip_nulls(jsonb_build_object('prix',price,'stock',stock,'ancien_prix',old_price));$b$],
  [$a$when entity_kind='produits' and r.statut='Épuisé' and stock>0 then 'Disponible'$a$,$b$when entity_kind='produits' and r.statut='Épuisé' and coalesce(stock,1)>0 then 'Disponible'$b$],
  [$a$set payload=(payload-'ancien_prix'-'zone'-'prix'-'localisation'-'horaires'-'whatsapp')||data$a$,$b$set payload=(payload-'ancien_prix'-'zone'-'prix'-'localisation'-'horaires'-'whatsapp'-'stock')||data$b$]];
 for i in 1..array_length(pairs,1) loop n:=(length(d)-length(replace(d,pairs[i][1],'')))/length(pairs[i][1]);if n<>1 then raise exception 'Préflight commerce_business % : % occurrence(s)',i,n;end if;d:=replace(d,pairs[i][1],pairs[i][2]);end loop;
 execute d;
 d:=pg_get_functiondef('koki_private.business'::regproc);
 pairs:=array[
  [$a$to_jsonb((payload->>'stock')::integer-qty)) where public.koki_records.id=r.id;$a$,$b$to_jsonb((payload->>'stock')::integer-qty)) where public.koki_records.id=r.id and payload->>'stock' is not null;$b$],
  [$a$+(line->>'quantity')::integer)) where public.koki_records.id=(line->>'product_id')::uuid;$a$,$b$+(line->>'quantity')::integer)) where public.koki_records.id=(line->>'product_id')::uuid and payload->>'stock' is not null;$b$]];
 for i in 1..array_length(pairs,1) loop n:=(length(d)-length(replace(d,pairs[i][1],'')))/length(pairs[i][1]);if n<>1 then raise exception 'Préflight business % : % occurrence(s)',i,n;end if;d:=replace(d,pairs[i][1],pairs[i][2]);end loop;
 execute d;
 d:=pg_get_functiondef('koki_private.commerce_admin_before_product_review'::regproc);
 pairs:=array[
  [$a$price:=case when input ? 'price' then koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide') else$a$,$b$price:=case when input ? 'price' and input->'price'<>'null'::jsonb then koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide') when input ? 'price' then null else$b$],
  [$a$stock:=case when input ? 'stock' then koki_private.commerce_int(input,'stock',1000000,'Stock invalide') else$a$,$b$stock:=case when input ? 'stock' and input->'stock'<>'null'::jsonb then koki_private.commerce_int(input,'stock',1000000,'Stock invalide') when input ? 'stock' then null else$b$],
  [$a$if old_price is not null and old_price<=price then raise$a$,$b$if old_price is not null and (price is null or old_price<=price) then raise$b$]];
 for i in 1..array_length(pairs,1) loop n:=(length(d)-length(replace(d,pairs[i][1],'')))/length(pairs[i][1]);if n<>1 then raise exception 'Préflight révision % : % occurrence(s)',i,n;end if;d:=replace(d,pairs[i][1],pairs[i][2]);end loop;
 execute d;
end $t$;

