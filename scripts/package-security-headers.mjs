import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

// Static-directory releases must carry the same policy as source-root releases.
export function staticDeploymentConfig(config){
  return {framework:null,buildCommand:null,outputDirectory:'.',headers:config.headers};
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
  const config=JSON.parse(await readFile(new URL('../vercel.json',import.meta.url),'utf8'));
  await writeFile(new URL('../dist/vercel.json',import.meta.url),JSON.stringify(staticDeploymentConfig(config),null,2)+'\n');
}
