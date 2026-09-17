import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {evaluate,readData,profile,jsonWrite,renderThemed,htmlDocument,PHASES} from './lib/project.mjs';
const [cmd,...args]=process.argv.slice(2); const root=process.cwd();
const usage='vl check | profile data.csv | phase question|data|encode|explore|polish|verify | snapshot [--theme dark] | export | help';
const report=state=>{console.log(state.verdict.summary);for(const f of state.verdict.findings)console.log(`${f.severity}: ${f.message}${f.ref?` [${f.ref}]`:''}`);};
try{
  if(cmd==='help' || !cmd){console.log(usage);}
  else if(cmd==='profile'){const {rows}=readData(root,args[0],{},{infer:true});console.log(JSON.stringify({rows:rows.length,columns:profile(rows),sample:rows.slice(0,5)},null,2));}
  else if(cmd==='phase'){
    if(!PHASES.some(p=>p.toLowerCase()===args[0]))throw Error(usage);
    const brief=JSON.parse(readFileSync('brief.json','utf8'));brief.stage=args[0];jsonWrite('brief.json',brief);
    const state=await evaluate(root);report(state);if(state.verdict.findings.some(f=>f.severity==='error'))process.exitCode=1;
  }else if(cmd==='snapshot'){
    const {snapshot}=await import('./lib/snapshot.mjs');const mode=args.includes('--theme')&&args[args.indexOf('--theme')+1]==='dark'?'dark':'light';
    const shot=await snapshot(root,{mode});console.log(`Wrote ${shot.image} (${shot.width}×${shot.height})${mode==='light'?` and .harness/review/request.md · chart ${shot.chartHash}`:''}`);
  }else if(cmd==='check' || cmd==='export'){
    const state=await evaluate(root);report(state);
    // `vl check` fails on errors so drafts can be checked; `--ready` (toolchain/check) fails until the chart is ready.
    const failed=state.verdict.findings.some(f=>f.severity==='error') || !state.svg || (args.includes('--ready')&&!state.verdict.ready);
    if(failed){process.exitCode=1;}
    else if(cmd==='export'){
      mkdirSync('exports',{recursive:true});const out=await renderThemed(state.spec);
      writeFileSync('exports/chart.svg',out.svg);jsonWrite('exports/chart.vg.json',out.compiled);jsonWrite('exports/chart.vl.json',out.themed);writeFileSync('exports/chart.html',htmlDocument(state.spec,state.brief));
      console.log('Exported exports/chart.svg, chart.vg.json, chart.vl.json and self-contained chart.html');
    }
  }else throw Error(usage);
}catch(e){console.error(`miss ${e.message.replaceAll(root,'workspace')}`);process.exitCode=1;}
