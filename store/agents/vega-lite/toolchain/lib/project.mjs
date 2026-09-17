import {readFileSync,writeFileSync,mkdirSync,renameSync,realpathSync,statSync,existsSync} from 'node:fs';
import {resolve,sep,extname,join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import * as vega from 'vega';
import * as vl from 'vega-lite';
import Ajv from 'ajv';
import addFormats from 'ajv-formats';
const require=createRequire(import.meta.url);
const packageDir=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
export const theme=require('../../viewer/theme.js');
const ajv=new Ajv({strict:false,allErrors:true}); addFormats(ajv); ajv.addFormat('color-hex',/^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i);
const validate=ajv.compile(JSON.parse(readFileSync(require.resolve('vega-lite/vega-lite-schema.json'))));
export const PHASES=['Question','Data','Encode','Explore','Polish','Verify'];
export const RUBRIC=join(packageDir,'skills/vega-lite/review-rubric.md');
export const REVIEW_DIR='.harness/review';
export const rubricCriteria=()=>[...readFileSync(RUBRIC,'utf8').matchAll(/^### `([a-z-]+)`/gm)].map(m=>m[1]);
const TOOL_KINDS=['input','schema','compiler_warning','render','runtime','empty_render','nonfinite_render'];
const CHECK_KINDS=['row_count','field','mark','param','panels','assertion','question','provenance'];
// The fresh reviewer's grade, if it is for this exact chart.
function readReview(root,chartHash){
  const file=join(root,REVIEW_DIR,'result.json');if(!existsSync(file))return {state:'missing'};
  let result;try{result=JSON.parse(readFileSync(file,'utf8'));}catch{return {state:'invalid',problem:'result.json is not valid JSON'};}
  if(result?.hash!==chartHash)return {state:'stale'};
  const ids=rubricCriteria();const criteria=Array.isArray(result.criteria)?result.criteria:[];
  const missing=ids.filter(id=>!criteria.some(c=>c?.id===id&&typeof c.passed==='boolean'));
  if(missing.length)return {state:'invalid',problem:`result.json does not grade ${missing.join(', ')}`};
  const graded=ids.map(id=>criteria.find(c=>c.id===id));
  return {state:'graded',passed:graded.every(c=>c.passed),criteria:graded.map(c=>({id:c.id,passed:c.passed,note:String(c.note||'')}))};
}
export function safeFile(root,name){
  if(typeof name!=='string' || !name || name.includes('\\') || /^(?:[a-z]+:|\/)/i.test(name) || name.split('/').some(x=>x.startsWith('.') || x==='node_modules')) throw Error('Use a workspace-relative public file path');
  const full=realpathSync(resolve(root,name)); const base=realpathSync(root)+sep;
  if(!full.startsWith(base) || !statSync(full).isFile()) throw Error('File must stay inside the workspace');
  if(statSync(full).size>32*1024*1024) throw Error('File exceeds the 32 MiB preview limit');
  return full;
}
export function jsonWrite(path,value){mkdirSync(resolve(path,'..'),{recursive:true}); const temp=path+`.${process.pid}.tmp`;writeFileSync(temp,JSON.stringify(value,null,2)+'\n');renameSync(temp,path);}
export function walk(value,fn,path='') {if(!value || typeof value!=='object') return; fn(value,path); for(const [k,v] of Object.entries(value)) if(k!=='values' && k!=='datasets') {if(Array.isArray(v)) v.forEach((x,i)=>walk(x,fn,`${path}/${k}/${i}`)); else if(v && typeof v==='object') walk(v,fn,`${path}/${k}`);}}
// Profiles (infer) read delimited text with Vega's type inference, so numbers show as numbers. Chart data keeps the chart's own format.
export function readData(root,name,format={},{infer=false}={}) {const raw=readFileSync(safeFile(root,name),'utf8'); const type=format.type || ({'.csv':'csv','.tsv':'tsv','.json':'json','.geojson':'json','.topojson':'topojson'}[extname(name)]); if(!type) throw Error('Data must be JSON, CSV, TSV or TopoJSON'); if(infer&&!format.parse&&['csv','tsv','dsv'].includes(type)){const rows=vega.read(raw,{...format,type});const columns=Object.keys(rows[0]||{});const types=vega.inferTypes(rows,columns);
    for(const c of columns){const t=types[c];if(!['boolean','integer','number'].includes(t)||rows.some(r=>/^[-+]?0\d/.test(r[c]??'')))continue;for(const r of rows)if(r[c]!=null&&r[c]!=='')r[c]=vega.typeParsers[t](r[c]);}
    return {raw,rows};}
  return {raw,rows:vega.read(raw,{...format,type})};}
export function profile(rows){
  if(!Array.isArray(rows)) return [];
  const names=[...new Set(rows.slice(0,50000).flatMap(row=>row && typeof row==='object'?Object.keys(row):[]))];
  return names.map(name=>{let missing=0;const types=new Set();for(const row of rows){const v=row?.[name]; if(v==null || v==='') missing++;else types.add(typeof v==='number'?'number':typeof v==='boolean'?'boolean':v instanceof Date||(typeof v==='string'&&/^\d{4}-\d{2}(-\d{2})?([T ][\d:.]+Z?)?$/.test(v))?'date':'text');}return {name,type:[...types].join(' / ')||'empty',missing};});
}
export function prepare(root){
  const input=[]; const load=(name)=>{const text=readFileSync(safeFile(root,name),'utf8');input.push(name,text);try{return JSON.parse(text);}catch(e){throw Object.assign(Error(`${name} is not valid JSON yet: ${e.message}`),{ref:name});}};
  const brief=load('brief.json');const tables=[];const seen=new Set();
  function table(name,rows){if(!seen.has(name)){seen.add(name);tables.push({name,rows:Array.isArray(rows)?rows:[],columns:profile(rows)});}}
  for(const name of brief.data||[]){const {raw,rows}=readData(root,name,{},{infer:true});input.push(name,raw);table(name,rows);}
  let source=null,spec=null;
  const artifact=brief.artifact || 'charts/main.vl.json';
  if(existsSync(resolve(root,artifact))){source=load(artifact);spec=structuredClone(source);
    walk(spec,(node,path)=>{
      if(node.url!==undefined && (path.endsWith('/data') || path.includes('/data/'))){
        const name=node.url; if(typeof name!=='string') throw Error('Dynamic data URLs are not supported; save local data');
        const {raw,rows}=readData(root,name,node.format);input.push(name,raw);table(name,rows);delete node.url;delete node.format;node.values=rows;
      } else if(node.url!==undefined) throw Error('External assets are not supported; keep the chart self-contained');
      if(node.data?.values!==undefined){const rows=typeof node.data.values==='string'?vega.read(node.data.values,node.data.format):node.data.values;table(path?`${path}/data`:'Inline data',rows);}
      if(node.mark==='image' || node.mark?.type==='image') throw Error('Image marks are not supported by the offline renderer');
    });
    for(const [name,rows] of Object.entries(spec.datasets||{}))table(name,rows);
  }
  const chartHash=spec?createHash('sha256').update(JSON.stringify(spec)).digest('hex').slice(0,16):'';
  return {brief,source,spec,artifact,tables,chartHash,hash:createHash('sha256').update(input.join('\n')).digest('hex')};
}
// Vega-Lite's schema is a union, so one mistake yields errors from every branch it tried. The mistake is the deepest
// place any branch complains about (a misspelt property counts as the property itself); at equal depth, the place most
// branches reject. Name it, set it aside, repeat, skipping complaints in that object, above it, or at the top level, which the mistake itself causes.
function schemaProblems(source){
  const errorsOf=spec=>{validate(spec);return (validate.errors||[]).filter(e=>!['anyOf','oneOf','required','if','then','else','not'].includes(e.keyword));};
  const target=e=>e.keyword==='additionalProperties'?`${e.instancePath}/${String(e.params.additionalProperty).replace(/~/g,'~0').replace(/\//g,'~1')}`:e.instancePath;
  const depth=path=>path.split('/').length;
  const messages=[];const touched=[];let spec=structuredClone(source);
  for(let round=0;round<6&&messages.length<4;round++){
    const errors=errorsOf(spec).filter(e=>{const t=target(e);return !(touched.length&&depth(t)<=2)&&!touched.some(parent=>t.startsWith(parent+'/')||parent===t||parent.startsWith(t+'/'));});if(!errors.length)break;
    const score=new Map();for(const e of errors){const t=target(e);const v=score.get(t)||{count:0,value:0};v.count++;if(e.keyword!=='additionalProperties')v.value=1;score.set(t,v);}
    const place=[...score.keys()].sort((x,y)=>depth(y)-depth(x)||score.get(y).count-score.get(x).count||score.get(y).value-score.get(x).value||x.localeCompare(y))[0];
    const here=errors.filter(e=>target(e)===place);const wrongValue=here.filter(e=>e.keyword!=='additionalProperties');
    if(wrongValue.length){
      const allowed=[...new Set(wrongValue.flatMap(e=>e.params.allowedValues||(e.params.allowedValue!==undefined?[e.params.allowedValue]:[])))];
      const kinds=[...new Set(wrongValue.filter(e=>e.keyword==='type').map(e=>e.params.type))];
      const options=[...kinds.map(k=>`${/^[aeiou]/.test(k)?'an':'a'} ${k}`),...allowed.slice(0,10).map(v=>JSON.stringify(v))];
      messages.push(`${place||'/'} ${options.length?`must be ${options.join(' or ')}${allowed.length>10?' …':''}`:wrongValue[0].message}`);
    }else messages.push(`${place.slice(0,place.lastIndexOf('/'))||'/'} has an unknown property "${here[0].params.additionalProperty}" (check its spelling and where it belongs)`);
    const cut=place.lastIndexOf('/');touched.push(place.slice(0,cut));const parent=cut>0?pointer(spec,place.slice(0,cut)):spec;const key=place.slice(cut+1).replace(/~1/g,'/').replace(/~0/g,'~');
    if(!parent||typeof parent!=='object'||!place)break;
    if(Array.isArray(parent))parent.splice(Number(key),1);else delete parent[key];
  }
  validate(source);
  return messages.length?messages:['The chart does not match the Vega-Lite 6 schema'];
}
function sceneMarks(scene){let count=0;const types=new Set();const visit=n=>{if(!n||typeof n!=='object')return;if(n.role==='mark' && n.marktype!=='group'){types.add(n.marktype);count+=(n.items||[]).length;}for(const item of n.items||[])visit(item);};visit(scene);return {count,types:[...types]};}
function pointer(obj,path){if(path==='') return obj; if(!path.startsWith('/')) return undefined;return path.slice(1).split('/').reduce((v,k)=>v?.[k.replace(/~1/g,'/').replace(/~0/g,'~')],obj);}
export async function evaluate(root,{write=true}={}){
  let project={brief:{},source:null,spec:null,artifact:'charts/main.vl.json',tables:[],hash:''};
  const findings=[];const checks=[];let compiled=null,svg=null,stats={rows:0,fields:0,marks:0,panels:0,params:[]};
  const add=(severity,kind,message,ref)=>findings.push({severity,kind,message,...(ref?{ref}:{})});
  try{project=prepare(root);}catch(e){add('error','input',e.message.replaceAll(root,'workspace'),e.ref||'brief.json');}
  const {brief,spec,source,tables,artifact}=project;
  stats.rows=tables.reduce((n,t)=>n+t.rows.length,0);stats.fields=new Set(tables.flatMap(t=>t.columns.map(c=>c.name))).size;
  const stageIndex=Math.max(0,PHASES.findIndex(x=>x.toLowerCase()===brief.stage));
  if(!spec) add('info','waiting',tables.length?'Data is ready; save the first chart to see its shape.':'Save the question and local data to begin.');
  if(spec){
    if(!validate(source)){
      for(const message of schemaProblems(source))add('error','schema',message,artifact);
    }else checks.push({name:'Vega-Lite schema',detail:'Valid against pinned 6.4.3 schema'});
    if(!findings.some(f=>f.severity==='error'))try{
      const warnings=[]; const logger={level(){return this},warn(...args){warnings.push(args.join(' '))},info(){},debug(){},error(...args){warnings.push(args.join(' '))}};
      compiled=vl.compile(spec,{logger}).spec;
      for(const msg of warnings)add('error','compiler_warning',msg,artifact);
      checks.push({name:'Compiler',detail:warnings.length?`${warnings.length} warnings`:'No compiler warnings'});
      const loader={...vega.loader(),load:async()=>{throw Error('Network data is disabled; save the data locally')}};
      const runtimeErrors=[];const runtimeLogger={level(){return vega.Warn},error(...args){runtimeErrors.push(args.map(String).join(' '));return this},warn(...args){const message=args.map(String).join(' ');if(message!=='Can not resolve event source: window')runtimeErrors.push(message);return this},info(){return this},debug(){return this}};
      const view=new vega.View(vega.parse(compiled),{renderer:'none',loader,logger:runtimeLogger});
      try{await view.runAsync();svg=await view.toSVG();const marks=sceneMarks(view.scenegraph().root);stats.marks=marks.count;
        if(!marks.count)add('error','empty_render','The SVG has no data marks; check fields, filters and types.',artifact);
        if(/(?:NaN|Infinity)/.test(svg))add('error','nonfinite_render','The SVG contains non-finite values.',artifact);
        for(const e of runtimeErrors)add('error','runtime',e,artifact);
        checks.push({name:'SVG rendering',detail:`${marks.count} rendered marks · ${svg.length.toLocaleString()} bytes`});
      }finally{view.finalize();}
    }catch(e){add('error','render',e.message.replaceAll(root,'workspace'),artifact);}
    const marks=new Set();const params=new Set();let panels=0;
    walk(source,node=>{if(node.mark){marks.add(typeof node.mark==='string'?node.mark:node.mark.type);panels++;}for(const p of node.params||[])params.add(p.name);});
    stats.params=[...params];stats.panels=panels;
    const req=brief.requirements||{};
    // The brief describes the finished chart. While drafting (before polish) an unmet requirement is a to-do, not a failure.
    const drafting=stageIndex<4;const need=(kind,message,ref)=>add(drafting?'info':'error',kind,drafting?`To do: ${message}`:message,ref);
    const fields=new Set(tables.flatMap(t=>t.columns.map(c=>c.name)));
    if(stats.rows<(req.minRows??1))need('row_count',`Expected at least ${req.minRows??1} input rows; found ${stats.rows}.`,'data');
    for(const f of req.fields||[])if(!fields.has(f))need('field',`Required input field missing: ${f}`,'data');
    for(const m of req.marks||[])if(!marks.has(m))need('mark',`Required mark missing: ${m}`,artifact);
    for(const p of req.params||[])if(!params.has(p))need('param',`Required parameter missing: ${p}`,artifact);
    if(panels<(req.minPanels??1))need('panels',`Expected at least ${req.minPanels} unit/layer specs; found ${panels}.`,artifact);
    for(const assertion of req.assertions||[]){const val=pointer(source,assertion.path||'');if(!Object.hasOwn(assertion,'equals') || JSON.stringify(val)!==JSON.stringify(assertion.equals))need('assertion',assertion.label||`Expected ${assertion.path} to equal ${JSON.stringify(assertion.equals)}`,artifact);}
    checks.push({name:'Brief requirements',detail:`${(req.fields||[]).length} fields · ${(req.marks||[]).length} mark types · ${(req.params||[]).length} parameters · ${(req.assertions||[]).length} exact assertions`});
    if(!brief.question?.trim()) add('error','question','Write the question in brief.json.','brief.json');
    if(!brief.source?.trim())add('error','provenance','State the data source; label synthetic data explicitly.','brief.json');
    if(!source.title)add('warning','title','Give the chart a title explaining its question or finding.',artifact);
    const missing=tables.flatMap(t=>t.columns.filter(c=>c.missing).map(c=>`${c.name}: ${c.missing}`));
    if(missing.length)add('warning','missing_data',`Missing values — ${missing.slice(0,6).join('; ')}. Document how these are handled.`,'data');
    if(stats.rows>50000)add('warning','large_data','More than 50,000 rows; aggregate for a responsive view.','data');
  }
  const errorsOf=kinds=>findings.filter(f=>f.severity==='error'&&kinds.includes(f.kind));
  const req=brief.requirements||{};const claims=4+(req.fields||[]).length+(req.marks||[]).length+(req.params||[]).length+(req.assertions||[]).length;
  let review={state:'missing'};
  if(spec){
    review=readReview(root,project.chartHash);
    if(review.state==='invalid')add('error','review_invalid',`The review cannot be used: ${review.problem}. Ask the reviewer to follow ${REVIEW_DIR}/request.md again.`,`${REVIEW_DIR}/result.json`);
    for(const c of review.criteria||[])if(!c.passed)add('error','review',`Review · ${c.id}: ${c.note||'did not pass'}`,'review-rubric.md');
    if(stageIndex===5&&review.state==='missing')add('info','review_pending','Machine checks run on every save. For ready, run `vl snapshot` and have a fresh reviewer follow .harness/review/request.md.',`${REVIEW_DIR}/request.md`);
    if(review.state==='stale')add(stageIndex===5?'warning':'info','review_stale','The review graded an earlier version of this chart. Snapshot and review again.',`${REVIEW_DIR}/result.json`);
  }
  const toolErrors=errorsOf(TOOL_KINDS).length,checkErrors=errorsOf(CHECK_KINDS).length;
  const todos=findings.filter(f=>f.severity==='info'&&CHECK_KINDS.includes(f.kind)).length;
  const evaluation=[
    {method:'tool',by:'the Vega-Lite 6.4.3 schema, compiler and Vega renderer',passed:spec?!toolErrors&&!!svg:null,gate:true,...(spec?{detail:toolErrors?`${toolErrors} problem${toolErrors===1?'':'s'} in the chart`:`${stats.marks} marks rendered`}:{})},
    {method:'checks',by:'the brief: rows, fields, marks, parameters, assertions',passed:spec&&!toolErrors&&!todos?!checkErrors:null,gate:true,...(spec&&!toolErrors?{detail:checkErrors?`${checkErrors} of ${claims} requirements not met`:todos?`${claims-todos} of ${claims} requirements met so far`:`${claims} requirements met`}:{})},
    {method:'review',by:'a chart-reading rubric, by a fresh-context reviewer',passed:review.state==='graded'?review.passed:review.state==='invalid'?false:null,gate:true,detail:review.state==='graded'?`${review.criteria.filter(c=>c.passed).length} of ${review.criteria.length} criteria passed`:review.state==='stale'?'graded an earlier version':review.state==='invalid'?'result could not be read':'not run yet'}
  ];
  const errors=findings.filter(f=>f.severity==='error').length;
  const ready=!!spec && !!svg && !errors && stageIndex===5 && evaluation.every(e=>!e.gate||e.passed===true);
  const phases=PHASES.map((name,i)=>({id:name.toLowerCase(),name,state:ready?'done':i<stageIndex?'done':i===stageIndex?(errors?'failed':'active'):'pending'}));
  const summary=errors?`${errors} ${errors===1?'check needs':'checks need'} attention`:ready?`Checked and reviewed · ${stats.rows} rows · ${stats.marks} marks`:spec&&stageIndex===5?`Machine checks passed · review ${review.state==='stale'?'out of date':'not run yet'}`:spec?`Draft · ${PHASES[stageIndex]} · ${stats.rows} rows`:tables.length?`${stats.rows} rows ready · waiting for a chart`:'Ready for a question · save data to begin';
  const verdict={spec:1,ready,summary,findings,artifact,phases,evaluation,updatedAt:new Date().toISOString()};
  const result={...project,compiled,svg,stats,checks,review,verdict};
  if(write){jsonWrite(join(root,'.harness/verdict.json'),verdict);jsonWrite(join(root,'.harness/checks.json'),{hash:project.hash,checks,stats,chartHash:project.chartHash,method:'tool, checks, review',limits:'Machine checks cover schema, compilation, rendering and declared requirements. The review reads a still image against a rubric. Neither proves the data is true or that every interaction works.'});}
  return result;
}

// Portable exports: the authored chart over the studio's light theme, rendered without network access.
export async function renderThemed(spec){
  const themed=theme.themed(spec,'light');const compiled=vl.compile(themed,{logger:{level(){return this},warn(){},info(){},debug(){},error(){}}}).spec;
  const loader={...vega.loader(),load:async()=>{throw Error('Network data is disabled; save the data locally')}};
  const view=new vega.View(vega.parse(compiled),{renderer:'none',loader,logger:{level(){return vega.Warn},error(){return this},warn(){return this},info(){return this},debug(){return this}}});
  try{await view.runAsync();return {themed,compiled,svg:await view.toSVG()};}finally{view.finalize();}
}
const escapeHTML=value=>String(value??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
// A self-contained, offline HTML page that follows the reader's light or dark preference.
export function htmlDocument(spec,brief={}){
  const script=code=>`<script>${code.replaceAll('</script','<\\/script')}</script>`;
  const bundles=['vega/build/vega.min.js','vega-lite/build/vega-lite.min.js','vega-embed/build/vega-embed.min.js'].map(p=>readFileSync(join(packageDir,'node_modules',p),'utf8'));
  const themeCode=readFileSync(join(packageDir,'viewer/theme.js'),'utf8');const light=theme.PALETTES.light,dark=theme.PALETTES.dark;
  const literal=JSON.stringify(spec).replaceAll('<','\\u003c');
  return `<!doctype html><!--\nChart built with Vega-Lite 6.4.3, Vega 6.4.0 and Vega-Embed 7.2.0, embedded verbatim below.\nCopyright (c) 2015-2023, University of Washington Interactive Data Lab. All rights reserved.\nUsed under the BSD 3-Clause Licence: https://github.com/vega/vega-lite/blob/v6.4.3/LICENSE\n--><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>${escapeHTML(brief.title||'Vega-Lite chart')}</title><style>:root{--bg:${light.background};--muted:${light.subtitle}}@media(prefers-color-scheme:dark){:root{--bg:${dark.background};--muted:${dark.subtitle}}}body{margin:0;background:var(--bg);font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}#chart{padding:32px;overflow:auto}footer{padding:0 32px 32px;font-size:12px;line-height:1.6;color:var(--muted)}</style></head><body><div id="chart"></div><footer>${brief.source?escapeHTML(brief.source)+' · ':''}Made with Vega-Lite (BSD-3-Clause) by Vega / UW Interactive Data Lab.</footer>${bundles.map(script).join('')}${script(themeCode)}<script>const spec=${literal};const media=matchMedia('(prefers-color-scheme: dark)');let result;async function draw(){const mode=media.matches?'dark':'light';result?.finalize();result=await vegaEmbed('#chart',VegaLiteStudioTheme.themed(spec,mode),{renderer:'svg',tooltip:{theme:mode},actions:{export:true,source:false,compiled:false,editor:false}});}media.addEventListener('change',draw);draw();</script></body></html>`;
}
