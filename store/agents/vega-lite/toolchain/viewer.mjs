import {createServer} from 'node:http';
import {readFileSync,watch,existsSync,readdirSync,statSync} from 'node:fs';
import {resolve,join,dirname,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {evaluate,safeFile,jsonWrite,htmlDocument} from './lib/project.mjs';
const root=resolve(process.env.HARNESS_WORKSPACE);const port=Number(process.env.HARNESS_VIEWER_PORT);
const pkg=resolve(dirname(fileURLToPath(import.meta.url)),'..');const page=join(pkg,'viewer');
const clients=new Set();let current=null,lastGood=null,revision=0,running=false,pending=false,timer;
const csp="default-src 'none'; script-src 'self' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data: blob:; font-src 'self'; base-uri 'none'; object-src 'none'; form-action 'none'";
function signal(){for(const client of clients)client.write(`event: change\ndata: ${revision}\n\n`);}
async function refresh(){
  if(running){pending=true;return;}running=true;
  if(current){current={...current,checking:true,verdict:{...current.verdict,ready:false,summary:'Checking the latest save…'}};jsonWrite(join(root,'.harness/verdict.json'),current.verdict);revision++;signal();}
  try{
    const next=await evaluate(root);
    if(next.svg && !next.verdict.findings.some(f=>['schema','render','runtime','empty_render','nonfinite_render'].includes(f.kind)))lastGood={spec:next.spec,source:next.source,svg:next.svg,compiled:next.compiled,hash:next.hash};
    current={...next,checking:false,displaySpec:lastGood?.spec||null,displayHash:lastGood?.hash||null,stale:!!lastGood && lastGood.hash!==next.hash};
  }catch(e){current={...current,checking:false,stale:!!lastGood,displaySpec:lastGood?.spec||null,verdict:{spec:1,ready:false,summary:'The latest save needs attention',findings:[{severity:'error',kind:'check',message:'Could not read the latest chart. Check the input files.'}],phases:[],updatedAt:new Date().toISOString()}};jsonWrite(join(root,'.harness/verdict.json'),current.verdict);}
  revision++;signal();running=false;if(pending){pending=false;refresh();}
}
// The review result lives under .harness/, which is otherwise ignored; its arrival changes the verdict.
const REVIEW_RESULT='.harness/review/result.json';
function changed(name){const parts=(name||'').split(/[\\/]/);if(parts.join('/')!==REVIEW_RESULT&&parts.some(p=>p.startsWith('.')||['node_modules','exports'].includes(p)))return;if(name && !/\.(json|csv|tsv|geojson|topojson)$/.test(name))return;clearTimeout(timer);timer=setTimeout(refresh,180);}
const vendor={'vega.js':'vega/build/vega.min.js','vega-lite.js':'vega-lite/build/vega-lite.min.js','vega-embed.js':'vega-embed/build/vega-embed.min.js'};
const server=createServer(async(req,res)=>{
  res.setHeader('Content-Security-Policy',csp);res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Cache-Control','no-store');
  const send=(code,type,body)=>{res.writeHead(code,{'Content-Type':type});res.end(body);};
  try{
    if(req.method!=='GET')return send(405,'text/plain','Read-only viewer');
    const url=new URL(req.url,'http://127.0.0.1');const pathname=decodeURIComponent(url.pathname);
    if(pathname==='/events'){res.writeHead(200,{'Content-Type':'text/event-stream',Connection:'keep-alive'});res.write(': connected\n\n');clients.add(res);req.on('close',()=>clients.delete(res));return;}
    if(pathname==='/state'){if(!current)await refresh();const state={...current,revision};delete state.svg;delete state.compiled;state.tables=(state.tables||[]).map(t=>({...t,totalRows:t.rows.length,rows:t.rows.slice(0,5000)}));return send(200,'application/json',JSON.stringify(state));}
    if(pathname.startsWith('/vendor/')){const name=pathname.slice(8);if(!vendor[name])return send(404,'text/plain','Not found');return send(200,'text/javascript',readFileSync(join(pkg,'node_modules',vendor[name])));}
    if(pathname==='/export/chart.html'){if(!lastGood)return send(404,'text/plain','No working chart yet');return send(200,'text/html',htmlDocument(lastGood.spec,current?.brief));}
    const files={'/':'index.html','/app.js':'app.js','/theme.js':'theme.js','/style.css':'style.css'};
    if(files[pathname])return send(200,pathname.endsWith('.js')?'text/javascript':pathname==='/style.css'?'text/css':'text/html',readFileSync(join(page,files[pathname])));
    if(pathname.startsWith('/files/')){const file=safeFile(root,pathname.slice(7));if(!['json','csv','tsv','svg','html','png'].includes(extname(file).slice(1)))return send(404,'text/plain','Not found');res.setHeader('Content-Disposition',`attachment; filename="${extname(file)==='.html'?'chart.html':'artifact'+extname(file)}"`);return send(200,'application/octet-stream',readFileSync(file));}
    return send(404,'text/plain','Not found');
  }catch(e){send(e instanceof URIError?400:404,'text/plain',e instanceof URIError?'Bad path encoding':'File is not available in this workspace');}
});
try{watch(root,{recursive:true},(_event,name)=>changed(name?.toString()));}catch{
  let previous='';setInterval(()=>{const entries=[];const scan=(dir,depth=0)=>{for(const entry of readdirSync(dir,{withFileTypes:true})){if(entry.name.startsWith('.')||['node_modules','exports'].includes(entry.name))continue;const file=join(dir,entry.name);if(entry.isDirectory()&&depth<5)scan(file,depth+1);else if(entry.isFile()&&/\.(json|csv|tsv)$/.test(file))entries.push(file+statSync(file).mtimeMs);}};scan(root);const review=join(root,REVIEW_RESULT);if(existsSync(review))entries.push(review+statSync(review).mtimeMs);const next=entries.join('|');if(next!==previous){previous=next;changed('');}},1000).unref();
}
setInterval(()=>{for(const client of clients)client.write(': ping\n\n');},15000).unref();
await refresh();server.listen(port,'127.0.0.1',()=>console.log('Vega-Lite pane ready'));
