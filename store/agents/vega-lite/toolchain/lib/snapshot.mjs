// A still picture of the chart, for the agent's own eyes and for the fresh reviewer.
// Vega lays text out with Inter's real advance widths, and resvg (WebAssembly) rasterises with the same font, offline.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import * as vega from 'vega';
import * as vl from 'vega-lite';
import opentype from 'opentype.js';
import {initWasm,Resvg} from '@resvg/resvg-wasm';
import {prepare,theme,RUBRIC,REVIEW_DIR,rubricCriteria} from './project.mjs';
const pkg=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const INTER={400:'400Regular/Inter_400Regular.ttf',500:'500Medium/Inter_500Medium.ttf',600:'600SemiBold/Inter_600SemiBold.ttf',700:'700Bold/Inter_700Bold.ttf'};
const quiet={level(){return this},warn(){return this},info(){return this},debug(){return this},error(){return this}};
let fonts=null;
async function loadFonts(){
  if(fonts)return fonts;
  const buffers=Object.fromEntries(Object.entries(INTER).map(([weight,file])=>[weight,readFileSync(join(pkg,'node_modules/@expo-google-fonts/inter',file))]));
  const faces=Object.fromEntries(Object.entries(buffers).map(([weight,b])=>[weight,opentype.parse(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength))]));
  // Per-glyph advances; opentype.js's shaping cannot read Inter's substitution tables, and kerning barely moves layout.
  const cache=new Map();
  const advance=(weight,ch)=>{const key=weight+ch;if(!cache.has(key)){const face=faces[weight];cache.set(key,face.charToGlyph(ch).advanceWidth/face.unitsPerEm);}return cache.get(key);};
  const weightOf=w=>{const n=w==='bold'?700:Number(w)||400;return n>=650?700:n>=550?600:n>=450?500:400;};
  vega.textMetrics.width=(item,text)=>{let total=0;const weight=weightOf(item.fontWeight);for(const ch of String(text??''))total+=advance(weight,ch);return total*(item.fontSize??11);};
  await initWasm(readFileSync(join(pkg,'node_modules/@resvg/resvg-wasm/index_bg.wasm')));
  fonts=Object.values(buffers).map(b=>new Uint8Array(b));
  return fonts;
}
export async function snapshot(root,{mode='light',scale=2,pad=24}={}){
  const project=prepare(root);
  if(!project.spec)throw Error(`Save the chart first (${project.artifact})`);
  const fontBuffers=await loadFonts();
  const compiled=vl.compile(theme.themed(project.spec,mode),{logger:quiet}).spec;
  const loader={...vega.loader(),load:async()=>{throw Error('Network data is disabled; save the data locally')}};
  const view=new vega.View(vega.parse(compiled),{renderer:'none',loader,logger:quiet});
  let svg;try{await view.runAsync();svg=await view.toSVG();}finally{view.finalize();}
  const [,width,height]=svg.match(/width="([\d.]+)" height="([\d.]+)"/).map(Number);
  const framed=`<svg xmlns="http://www.w3.org/2000/svg" width="${width+2*pad}" height="${height+2*pad}"><rect width="100%" height="100%" fill="${theme.PALETTES[mode].background}"/>${svg.replace('<svg ',`<svg x="${pad}" y="${pad}" `)}</svg>`;
  const png=new Resvg(framed,{fitTo:{mode:'zoom',value:scale},font:{fontBuffers,loadSystemFonts:false,defaultFontFamily:'Inter',sansSerifFamily:'Inter'}}).render().asPng();
  mkdirSync(join(root,REVIEW_DIR),{recursive:true});
  const image=`${REVIEW_DIR}/chart${mode==='dark'?'-dark':''}.png`;writeFileSync(join(root,image),png);
  if(mode==='light')writeFileSync(join(root,REVIEW_DIR,'request.md'),request(project,image));
  return {image,width:Math.round((width+2*pad)*scale),height:Math.round((height+2*pad)*scale),chartHash:project.chartHash};
}
function request({brief,chartHash},image){
  const rubric=readFileSync(RUBRIC,'utf8').replace(/^# .*\n+/,'');
  const shape=JSON.stringify({hash:chartHash,passed:false,criteria:rubricCriteria().map(id=>({id,passed:true,note:'…'}))});
  return `# Review this chart

You are a fresh reviewer. You have not seen how this chart was made, and that is the point: read it the way its audience will.

1. Open the image \`${image}\` and look at it closely. It is the chart at 2× scale on its light background.
2. Read the brief and the rubric below.
3. Grade every rubric criterion as passed or failed, with a one-line note. A failing note says exactly what to change.
4. Write \`${REVIEW_DIR}/result.json\` in this shape, with \`passed\` true only when every criterion passed. The hash must stay \`${chartHash}\`:

\`\`\`json
${shape}
\`\`\`

Do not edit any other file. Do not try to fix the chart.

## The brief

- **Question:** ${brief.question||'(none given)'}
- **Title:** ${brief.title||'(none given)'}
- **What a reader can do:** ${brief.description||'(none given)'}
- **Source:** ${brief.source||'(none given)'}

## The rubric

${rubric}`;
}
