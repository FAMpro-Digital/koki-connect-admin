import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
test('quota reste actif après suppression ; modération protégée et masquage effectif',async()=>{
 const db=new PGlite();try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema koki_private;create table auth.users(id uuid primary key,is_anonymous boolean);create function auth.uid() returns uuid language sql as $$select '11111111-1111-4111-8111-111111111111'::uuid$$;create function koki_private.allowed(text) returns boolean language sql as $$select coalesce(current_setting('test.admin',true),'false')='true'$$;create table public.koki_contents(id uuid primary key,statut text,publication timestamptz,type text,actif boolean,fin timestamptz);insert into auth.users values('11111111-1111-4111-8111-111111111111',false);insert into public.koki_contents values('22222222-2222-4222-8222-222222222222','publié',now(),'Actualités',true,null);`);
 await db.exec(await readFile(new URL('../supabase/proposals/publication-interactions.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../supabase/proposals/publication-moderation.sql',import.meta.url),'utf8'));
 const id='22222222-2222-4222-8222-222222222222';
 for(let i=0;i<5;i++){const r=await db.query('select public.koki_content_social($1, $2, $3) as r',[id,'comment','Test']);if(i<4)await db.query('select public.koki_content_social($1,$2,null,$3)',[id,'delete',r.rows[0].r.comments[0].id]);}
 await assert.rejects(db.query('select public.koki_content_social($1,$2,$3)',[id,'comment','Sixième']),/Trop de commentaires/);
 await assert.rejects(db.query('select public.koki_comment_moderation()'),/Accès refusé/);
 await db.exec("set test.admin='true'");
 const comment=(await db.query('select public.koki_comment_moderation() as r')).rows[0].r[0];
 await db.query('select public.koki_content_social($1,$2,$3,$4)',[id,'report','Contenu offensant',comment.id]);
 await db.query('select public.koki_comment_moderation($1,true,$2)',[comment.id,'Contenu inapproprié']);
 assert.equal((await db.query('select public.koki_content_social($1) as r',[id])).rows[0].r.total,0);
 assert.equal((await db.query('select count(*)::int as n from koki_social_private.moderation_log')).rows[0].n,1);
 await db.query('select public.koki_comment_moderation($1,false,$2)',[comment.id,'Réexamen terminé']);
 assert.equal((await db.query('select public.koki_content_social($1) as r',[id])).rows[0].r.total,1);
 }finally{await db.close();}
});
