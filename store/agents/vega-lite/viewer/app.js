const $=id=>document.getElementById(id);
const snapshot=new URLSearchParams(location.search).has('snapshot');if(snapshot)document.documentElement.dataset.snapshot='true';
let state=null,embed=null,tab='chart',renderKey='',renderToken=0,exploring=false,zoom=1,fitMode=true,chartSize={width:800,height:400},selectedTable=0,filteredRows=[],sortField=null,sortDirection=1,hasChart=false,lastRevision=-1,loading=false,queued=false;
const escapeHTML=value=>String(value??'').replace(/[&<>"\']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const format=value=>value==null?'—':typeof value==='number'?value.toLocaleString():typeof value==='object'?JSON.stringify(value):String(value);
const themeMode=()=>document.documentElement.dataset.theme||(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');
function toast(message){$('toast').textContent=message;$('toast').hidden=false;setTimeout(()=>{$('toast').hidden=true},3000);}
function setTab(name){tab=name;document.querySelectorAll('[data-tab]').forEach(button=>{const active=button.dataset.tab===name;button.classList.toggle('active',active);button.setAttribute('aria-selected',active);});for(const name of ['chart','data','spec','checks'])$(name+'-tab').hidden=tab!==name;if(tab==='chart')requestAnimationFrame(sizeChart);}
// Fit sizes the chart to the canvas width: never below 1× for a chart that fits, smaller only when it is wider than the pane.
// The canvas grows to the bottom of the first screen and scrolls vertically for taller compositions.
function sizeChart(){if(!embed)return;const canvas=$('canvas');const css=getComputedStyle(canvas);const padY=parseFloat(css.paddingTop)+parseFloat(css.paddingBottom);const width=canvas.clientWidth-parseFloat(css.paddingLeft)-parseFloat(css.paddingRight);
  const room=Math.max(innerHeight-(canvas.getBoundingClientRect().top+scrollY)-58,innerHeight*.5);
  // A chart that fits the first screen at 1× or more is enlarged only as far as it still fits; a taller one fills the width and scrolls.
  if(fitMode){const byWidth=Math.min(width/chartSize.width,1.35);const byRoom=(room-padY)/chartSize.height;
    // A picture cannot be scrolled: in snapshot mode the whole chart goes in the frame, down to a legible floor.
    zoom=snapshot?Math.max(Math.min(byWidth,byRoom),.62):byWidth>1&&byRoom>=1?Math.min(byWidth,byRoom):byWidth;}zoom=Math.max(.15,zoom);
  if(!$('chart-tab').hidden){const wanted=Math.round(Math.max(390,Math.min(chartSize.height*zoom+padY,room)));if(Math.abs(canvas.clientHeight-wanted)>1)canvas.style.height=wanted+'px';}
  $('chart').style.transform=`scale(${zoom})`;$('chart-shell').style.width=`${chartSize.width*zoom}px`;$('chart-shell').style.height=`${chartSize.height*zoom}px`;$('fit').textContent=fitMode?'Fit':`${Math.round(zoom*100)}%`;requestAnimationFrame(moreBelow);}
function moreBelow(){const c=$('canvas');c.classList.toggle('more-below',c.scrollTop+c.clientHeight<c.scrollHeight-4);}
function explorationSpec(input){const spec=structuredClone(input);if(!exploring||!spec.mark)return spec;spec.params=[...(spec.params||[])];const axes=['x','y'].filter(k=>['quantitative','temporal'].includes(spec.encoding?.[k]?.type));if(axes.length)spec.params.push({name:'_studio_zoom',select:{type:'interval',encodings:axes},bind:'scales'});const color=spec.encoding?.color;if(color?.field&&color.type==='nominal'&&!spec.encoding.opacity){spec.params.push({name:'_studio_series',select:{type:'point',fields:[color.field]},bind:'legend'});spec.encoding.opacity={condition:{param:'_studio_series',value:1},value:.15};}if(typeof spec.mark==='string')spec.mark={type:spec.mark,tooltip:true};else if(spec.mark.tooltip===undefined)spec.mark.tooltip=true;return spec;}
// Carry selections across a theme switch. Only Vega-Lite's selection state moves: each <param>_store dataset and
// the brush extents <param>_x, _y and _<field>. Restoring layout or derived signals stops the new view from redrawing.
const TRANSIENT=/_(tuple|tuple_fields|modify|scale_trigger|translate_anchor|translate_delta|zoom_anchor|zoom_delta|toggle)$/;
function restoreState(view,saved){
  const params=new Set();const collect=st=>{for(const name of Object.keys(st?.data||{}))if(name.endsWith('_store'))params.add(name.slice(0,-6));(st?.subcontext||[]).forEach(collect);};collect(saved);
  const apply=(ctx,st)=>{if(!ctx||!st)return;
    for(const [name,values] of Object.entries(st.data||{}))if(name.endsWith('_store')&&ctx.data[name])view.pulse(ctx.data[name].input,view.changeset().remove(()=>true).insert(values));
    for(const [name,value] of Object.entries(st.signals||{}))if(ctx.signals[name]&&!TRANSIENT.test(name)&&[...params].some(p=>name.startsWith(p+'_')))view.update(ctx.signals[name],value);
    (st.subcontext||[]).forEach((sub,i)=>apply(ctx.subcontext?.[i],sub));};
  apply(view._runtime,saved);return view.runAsync();
}
async function renderChart(force=false){
  const input=state?.displaySpec;if(!input){$('chart-shell').hidden=true;$('empty').hidden=false;return;}
  const mode=themeMode();const key=state.displayHash+String(exploring)+mode;if(!force&&key===renderKey)return;
  const keepState=!force&&embed&&renderKey===state.displayHash+String(exploring)+(mode==='dark'?'light':'dark');let previous=null;if(keepState)try{previous=embed.view.getState({data:(name,data)=>data.modified&&Array.isArray(data.input.value)&&!name.startsWith('_:vega:_'),signals:(name,op)=>!['parent','background'].includes(name)&&!(op instanceof vega.transforms.proxy),recurse:true});}catch{}
  const token=++renderToken;const staging=document.createElement('div');staging.style.cssText='position:absolute;visibility:hidden;left:0;top:0;';staging.style.width=Math.max(400,$('canvas').clientWidth-64)+'px';$('canvas').appendChild(staging);
  try{
    const next=await vegaEmbed(staging,VegaLiteStudioTheme.themed(explorationSpec(input),mode),{renderer:'svg',actions:false,tooltip:{theme:mode}});
    if(token!==renderToken){next.finalize();staging.remove();return;}
    if(previous)try{await restoreState(next.view,previous);}catch{}
    embed?.finalize();embed=next;staging.style.cssText='';$('chart').replaceChildren(staging);
    const svg=$('chart').querySelector('svg');chartSize={width:Number(svg?.getAttribute('width'))||800,height:(Number(svg?.getAttribute('height'))||400)+($('chart').querySelector('.vega-bindings')?.offsetHeight||0)};
    $('chart-shell').hidden=false;$('empty').hidden=true;renderKey=key;hasChart=true;fitMode=true;sizeChart();
    $('render-state').textContent='SVG · crisp at every scale';
  }catch(error){staging.remove();$('error-banner').hidden=false;$('error-banner').textContent='Preview could not render this save. The previous chart is kept. '+error.message;$('render-state').textContent='Preview needs attention';}
}
function dataTable(){const table=state?.tables?.[selectedTable];if(!table){$('table-wrap').innerHTML='<div class="data-empty">Save local data to inspect its rows and fields.</div>';$('data-count').textContent='';$('table-note').textContent='No data has been saved yet.';return;}
  const query=$('search').value.toLowerCase();filteredRows=table.rows.filter(row=>Object.values(row??{}).some(value=>format(value).toLowerCase().includes(query)));
  if(sortField)filteredRows.sort((a,b)=>{const av=a?.[sortField],bv=b?.[sortField];return sortDirection*(typeof av==='number'&&typeof bv==='number'?av-bv:String(av??'').localeCompare(String(bv??''),undefined,{numeric:true}));});
  const shown=filteredRows.slice(0,250);$('data-count').textContent=`${filteredRows.length.toLocaleString()} rows`;
  $('table-wrap').innerHTML=`<table><thead><tr><th>#</th>${table.columns.map(c=>`<th data-field="${escapeHTML(c.name)}" tabindex="0" aria-label="Sort by ${escapeHTML(c.name)}">${escapeHTML(c.name)} ${sortField===c.name?(sortDirection===1?'↑':'↓'):'↕'}<small>${escapeHTML(c.type)}${c.missing?` · ${c.missing} missing`:''}</small></th>`).join('')}</tr></thead><tbody>${shown.map((row,i)=>`<tr><td>${i+1}</td>${table.columns.map(c=>`<td title="${escapeHTML(format(row?.[c.name]))}">${escapeHTML(format(row?.[c.name]))}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
  $('table-note').textContent=`Showing ${shown.length} of ${filteredRows.length.toLocaleString()} matching rows${table.totalRows>5000?` · preview limited to 5,000 of ${table.totalRows.toLocaleString()}`:''} · click a column to sort`;
  $('table-wrap').querySelectorAll('th[data-field]').forEach(th=>{const sort=()=>{sortDirection=sortField===th.dataset.field?-sortDirection:1;sortField=th.dataset.field;dataTable();};th.onclick=sort;th.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();sort();}};});
}
function paint(next){
  const previousHadData=!!state?.tables?.length;state=next;const brief=state.brief||{};const verdict=state.verdict||{};const stats=state.stats||{};const errors=(verdict.findings||[]).filter(f=>f.severity==='error');
  $('title').textContent=brief.question?brief.title||'A question, made visible':'Make room for a new insight.';
  $('description').textContent=brief.question?brief.description||brief.question:'Your data becomes a chart here, one thoughtful step at a time.';$('description').title=$('description').textContent;
  $('question').textContent=brief.question||'What would you like to understand?';$('source-note').textContent=brief.source||'Your source and assumptions will stay beside the chart.';
  $('file-label').textContent=state.spec?state.artifact:'';$('status').textContent=state.checking?'Checking latest save…':verdict.ready?'✓  Checks passed':errors.length?`${errors.length} ${errors.length===1?'check needs':'checks need'} attention`:state.spec?'Work in progress':state.tables?.length?'Data ready':'Waiting for data';$('status').className='status '+(verdict.ready?'ready':errors.length?'failed':'');
  $('phases').innerHTML=(verdict.phases||[]).map((p,i)=>`<div class="phase ${p.state}" aria-label="${p.name}: ${p.state}"><b>${p.state==='done'?'✓':String(i+1).padStart(2,'0')}</b>${p.name}</div>`).join('');
  for(const key of ['rows','fields','marks'])$(key).textContent=stats[key]?stats[key].toLocaleString():'—';
  $('row-badge').textContent=stats.rows?stats.rows.toLocaleString():'';$('check-badge').textContent=errors.length||verdict.ready?(errors.length||'✓'):'';
  $('error-banner').hidden=!errors.length;$('error-banner').textContent=(state.stale?'Showing the last working chart. ':'')+errors.slice(0,2).map(f=>`${f.message}${f.ref?` (${f.ref})`:''}`).join(' · ');$('canvas').classList.toggle('stale',!!state.stale);
  $('source').textContent=state.source?JSON.stringify(state.source,null,2):'The Vega-Lite specification will appear after the first chart save.';
  const verb={tool:'Verified by',checks:'Checked against',review:'Reviewed against'};
  $('evaluation').innerHTML=(verdict.evaluation||[]).map(e=>`<div class="eval-row ${e.passed===true?'pass':e.passed===false?'fail':'wait'}"><span>${e.passed===true?'✓':e.passed===false?'✕':'○'}</span><div><strong>${escapeHTML(verb[e.method]||e.method)} ${escapeHTML(e.by)}</strong><p>${escapeHTML(e.passed===null&&!e.detail?'not run yet':e.detail||'')}</p></div></div>`).join('');
  $('review-notes').innerHTML=(state.review?.criteria||[]).map(c=>`<div class="criterion ${c.passed?'pass':'fail'}"><b>${c.passed?'✓':'✕'} ${escapeHTML(c.id[0].toUpperCase()+c.id.slice(1).replaceAll('-',' '))}</b><span>${escapeHTML(c.note)}</span></div>`).join('');
  $('checks-list').innerHTML=(state.checks||[]).map(c=>`<div class="check-row"><span>✓</span><div><strong>${escapeHTML(c.name)}</strong><p>${escapeHTML(c.detail)}</p></div></div>`).join('');
  $('findings').innerHTML=(verdict.findings||[]).map(f=>`<div class="check-row finding ${f.severity}"><span>${f.severity==='error'?'!':f.severity==='warning'?'△':'·'}</span><div><strong>${escapeHTML(f.message)}</strong><p>${escapeHTML(f.ref||f.kind)}</p></div></div>`).join('');
  const options=(state.tables||[]).map((t,i)=>`<option value="${i}">${escapeHTML(t.name)}</option>`).join('');if($('table-select').innerHTML!==options){$('table-select').innerHTML=options;selectedTable=Math.min(selectedTable,Math.max(0,(state.tables||[]).length-1));$('table-select').value=selectedTable;}
  $('field-list').innerHTML=(state.tables?.[0]?.columns||[]).slice(0,5).map(c=>`<div class="field-row"><span>${escapeHTML(c.name)}</span><span>${escapeHTML(c.type)}</span></div>`).join('');
  $('field-list').hidden=!state.tables?.length;dataTable();
  $('trust-title').textContent=verdict.ready?'Checked, not taken on faith':'Built to be inspected';$('trust-text').textContent=verdict.ready?'Machine checks and a fresh reviewer passed it. Whether the data is true still needs human judgment.':'Every save is checked. Source, data and findings stay a click away.';
  const params=stats.params||[];$('interaction-note').hidden=!params.length;$('interaction-note').textContent=params.length?`${params.length} authored interaction${params.length===1?'':'s'} · use the chart controls to explore`:'';
  const isUnit=!!state.displaySpec?.mark;$('explore').disabled=!isUnit;$('explore').title=isUnit?'Temporary axis zoom and series highlighting (not exported)':'Composed charts use their authored brush, legend and filter controls';
  $('gesture').textContent=exploring?'Explore preview · wheel to zoom, drag to pan, click a legend to highlight. Exports keep original source.':params.length?'Hover for values · use the chart’s brush, legend, or filter controls · R to reset.':'Hover marks to inspect values · open Data to see every input.';
  $('chart-mode').textContent=exploring?'Explore preview · source unchanged':'Interactive canvas';$('save-state').textContent=state.hash?`Live save · ${state.hash.slice(0,7)}`:'Waiting for the first save';
  $('download').disabled=!state.displaySpec;$('reset').disabled=!state.displaySpec;
  if(state.tables?.length&&!state.displaySpec&&!previousHadData)setTab('data');
  if(state.displaySpec&&!hasChart)setTab('chart');
  renderChart();
}
async function update(){if(loading){queued=true;return;}loading=true;try{const response=await fetch('/state');if(!response.ok)throw Error('Connection unavailable');const next=await response.json();if(next.revision!==lastRevision){lastRevision=next.revision;paint(next);}}catch{$('save-state').textContent='Connection interrupted · retrying automatically';}finally{loading=false;if(queued){queued=false;update();}}}
function download(blob,name){const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);}
async function exportChart(kind){$('export-menu').hidden=true;if(!embed||!state.displaySpec)return;try{if(kind==='svg')download(new Blob([await embed.view.toSVG()],{type:'image/svg+xml'}),'chart.svg');if(kind==='png'){const a=document.createElement('a');a.href=await embed.view.toImageURL('png',2);a.download='chart.png';a.click();}if(kind==='json')download(new Blob([JSON.stringify(VegaLiteStudioTheme.themed(state.displaySpec,'light'),null,2)],{type:'application/json'}),'chart.vl.json');if(kind==='html'){const response=await fetch('/export/chart.html');if(!response.ok)throw Error('the last working chart is not available');download(await response.blob(),'chart.html');}toast('Export downloaded');}catch(e){toast('Export failed: '+e.message);}}
for(const button of document.querySelectorAll('[data-tab]'))button.onclick=()=>setTab(button.dataset.tab);
$('open-data').onclick=()=>setTab('data');$('search').oninput=dataTable;$('table-select').onchange=()=>{selectedTable=Number($('table-select').value);sortField=null;dataTable();};
$('fit').onclick=()=>{fitMode=true;sizeChart();};$('zoom-in').onclick=()=>{fitMode=false;zoom=Math.min(4,zoom*1.2);sizeChart();};$('zoom-out').onclick=()=>{fitMode=false;zoom=Math.max(.15,zoom/1.2);sizeChart();};$('reset').onclick=()=>{renderChart(true);toast('Chart selections reset');};
$('explore').onclick=()=>{exploring=!exploring;$('explore').setAttribute('aria-pressed',exploring);renderKey='';paint(state);};
$('theme').onclick=()=>{const dark=document.documentElement.dataset.theme?document.documentElement.dataset.theme==='dark':matchMedia('(prefers-color-scheme:dark)').matches;document.documentElement.dataset.theme=dark?'light':'dark';renderChart();};
matchMedia('(prefers-color-scheme: dark)').addEventListener('change',()=>{if(!document.documentElement.dataset.theme)renderChart();});
$('download').onclick=()=>{$('export-menu').hidden=!$('export-menu').hidden;};document.querySelectorAll('[data-export]').forEach(b=>b.onclick=()=>exportChart(b.dataset.export));
$('copy').onclick=async()=>{try{await navigator.clipboard.writeText($('source').textContent);toast('Source copied');}catch{toast('Select and copy the source text below.');}};
$('csv').onclick=()=>{const columns=state.tables?.[selectedTable]?.columns||[];const quote=v=>'"'+String(v??'').replaceAll('"','""')+'"';download(new Blob([[columns.map(c=>quote(c.name)).join(','),...filteredRows.map(row=>columns.map(c=>quote(row[c.name])).join(','))].join('\n')],{type:'text/csv'}),'visible-rows.csv');};
document.addEventListener('click',e=>{if(!e.target.closest('.top-actions'))$('export-menu').hidden=true;});document.addEventListener('keydown',e=>{if(['INPUT','SELECT','TEXTAREA'].includes(e.target.tagName)||e.metaKey||e.ctrlKey||e.altKey)return;const key=e.key.toLowerCase();if(key==='t')$('theme').click();if(key==='f')$('fit').click();if(key==='r')$('reset').click();if(key==='d')setTab(tab==='data'?'chart':'data');if(key==='+'||key==='=')$('zoom-in').click();if(key==='-')$('zoom-out').click();if(key==='escape')$('export-menu').hidden=true;});
new ResizeObserver(()=>sizeChart()).observe($('canvas'));$('canvas').addEventListener('scroll',moreBelow,{passive:true});
const events=new EventSource('/events');events.addEventListener('change',update);events.onopen=update;setInterval(update,3000);update();
