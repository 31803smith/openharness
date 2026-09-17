import * as vl from 'vega-lite';
import * as vega from 'vega';
import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
const require=createRequire(import.meta.url);
try {
  if(vl.version!=='6.4.3' || vega.version!=='6.4.0') throw Error('version mismatch');
  const ajv=new Ajv({strict:false}); addFormats(ajv); ajv.addFormat('color-hex',/^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i);
  const validate=ajv.compile(JSON.parse(readFileSync(require.resolve('vega-lite/vega-lite-schema.json'))));
  const spec={data:{values:[{x:'A',y:2}]},mark:'bar',encoding:{x:{field:'x',type:'nominal'},y:{field:'y',type:'quantitative'}}};
  if(!validate(spec)) throw Error('schema validator failed');
  const view=new vega.View(vega.parse(vl.compile(spec).spec),{renderer:'none'});
  await view.runAsync(); const svg=await view.toSVG(); view.finalize();
  if(!svg.includes('role-mark')) throw Error('SVG has no marks');
  const embedPath=require.resolve('vega-embed');
  if(!readFileSync(embedPath).length) throw Error('missing Vega-Embed');
  console.log(`ok   Vega-Lite ${vl.version} / Vega ${vega.version} — schema, compiler and SVG render`);
  console.log('ok   Vega-Embed 7.2.0 — local browser bundle available');
  const {initWasm,Resvg}=await import('@resvg/resvg-wasm');const {default:opentype}=await import('opentype.js');
  const font=readFileSync(require.resolve('@expo-google-fonts/inter/400Regular/Inter_400Regular.ttf'));
  if(!opentype.parse(font.buffer.slice(font.byteOffset,font.byteOffset+font.byteLength)).charToGlyph('M').advanceWidth)throw Error('Inter font unreadable');
  await initWasm(readFileSync(require.resolve('@resvg/resvg-wasm/index_bg.wasm')));
  const png=new Resvg(svg,{font:{fontBuffers:[new Uint8Array(font)],loadSystemFonts:false,defaultFontFamily:'Inter'}}).render().asPng();
  if(png.length<200)throw Error('snapshot renderer produced no image');
  console.log('ok   resvg 2.6.2 (WebAssembly) and Inter — chart snapshots');
} catch(e) {console.error(`miss Vega toolchain — ${e.message}; run toolchain/setup.sh`); process.exit(1);}
