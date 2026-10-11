import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source=readFileSync(new URL('../src/app.js',import.meta.url),'utf8');
const screen=source.slice(source.indexOf('function screen()'),source.indexOf('async function guard()'));
function element(tag,text){return {tag,text,children:[],attributes:{},append(...items){this.children.push(...items);},setAttribute(k,v){this.attributes[k]=v;},classList:{add(){}},querySelector(){return this.header??=element('header');}};}
function render(current){
 const root=element('root');
 vm.runInNewContext(screen+';screen();',{root,current,account:null,configured:false,resources:{professionnels:{label:'Professionnels'},chauffeurs:{label:'Chauffeurs'},vehicules:{label:'Véhicules'},courses:{label:'Courses'}},n:element,button:(text,fn)=>({...element('button',text),onclick:fn}),shell(){},can:()=>false,navigate(){}});
 return root.children.find(e=>e.id==='shell').children[0];
}
test('Chauffeurs, Véhicules et Courses sont regroupés uniquement sous TRANSPORT',()=>{
 const side=render('dashboard');
 const group=side.children.find(e=>e.tag==='details');
 assert.equal(group.children[0].text,'🚕 TRANSPORT');
 assert.deepEqual(Array.from(group.children[1].children,e=>e.text),['Chauffeurs','Véhicules','Courses']);
 assert.equal(group.open,false);
 assert.ok(!side.children.some(e=>e.tag==='button'&&['Chauffeurs','Véhicules','Courses'].includes(e.text)));
});
test('La rubrique active ouvre TRANSPORT et reste identifiée',()=>{
 for(const key of ['chauffeurs','vehicules','courses']){
  const group=render(key).children.find(e=>e.tag==='details');
  assert.equal(group.open,true);
  assert.equal(group.children[1].children.filter(e=>e.attributes['aria-current']==='page').length,1);
 }
});
