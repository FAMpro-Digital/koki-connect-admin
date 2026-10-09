import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {staticDeploymentConfig} from '../scripts/package-security-headers.mjs';

const config=JSON.parse(await readFile(new URL('../vercel.json',import.meta.url),'utf8'));
const headers=Object.fromEntries(config.headers[0].headers.map(x=>[x.key.toLowerCase(),x.value]));
const directives=Object.fromEntries(headers['content-security-policy'].split(';').map(x=>x.trim().split(/\s+/)).filter(x=>x[0]).map(([name,...values])=>[name,values]));

test('static deployment packages the authoritative policy without trying to rebuild dist',async()=>{
  const packed=staticDeploymentConfig(config);
  assert.deepEqual(packed.headers,config.headers);
  assert.equal(packed.framework,null);
  assert.equal(packed.buildCommand,null);
  assert.equal(packed.outputDirectory,'.');
  const pkg=JSON.parse(await readFile(new URL('../package.json',import.meta.url),'utf8'));
  assert.equal(pkg.scripts.postbuild,'node scripts/package-security-headers.mjs');
});

test('deployment builds from project root with security headers covering all routes',()=>{
  assert.equal(config.framework,'vite');
  assert.equal(config.buildCommand,'npm run build');
  assert.equal(config.outputDirectory,'dist');
  assert.equal(config.headers[0].source,'/(.*)');
  assert.equal(headers['x-frame-options'],'DENY');
  assert.equal(headers['x-content-type-options'],'nosniff');
  assert.equal(headers['referrer-policy'],'no-referrer');
});

test('CSP denies script injection, frames, plugins and unrelated backend origins',()=>{
  for(const key of ['default-src','script-src','style-src'])assert.deepEqual(directives[key],["'self'"]);
  for(const key of ['object-src','base-uri','frame-ancestors'])assert.deepEqual(directives[key],["'none'"]);
  assert.deepEqual(directives['form-action'],["'self'"]);
  assert.deepEqual(directives['connect-src'],["'self'",'https://qsbmzzbiztfqysstepxm.supabase.co','wss://qsbmzzbiztfqysstepxm.supabase.co']);
  assert.deepEqual(directives['img-src'],["'self'",'data:','blob:','https://qsbmzzbiztfqysstepxm.supabase.co']);
});

test('entry document keeps executable scripts external for strict CSP',async()=>{
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  const scripts=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
  assert.ok(scripts.length);
  for(const [,attributes,body]of scripts){assert.match(attributes,/src="\/[^" ]+"/);assert.equal(body.trim(),'');}
  assert.doesNotMatch(html,/\son\w+\s*=|<style\b|\sstyle\s*=/i);
});
