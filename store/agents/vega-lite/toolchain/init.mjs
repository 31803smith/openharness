import {mkdirSync,existsSync,writeFileSync} from 'node:fs';
const phases=['Question','Data','Encode','Explore','Polish','Verify'].map((name,i)=>({id:name.toLowerCase(),name,state:i?'pending':'active'}));
mkdirSync('.harness',{recursive:true});
for(const dir of ['data','charts','exports']) mkdirSync(dir,{recursive:true});
if(!existsSync('.harness/verdict.json')) writeFileSync('.harness/verdict.json',JSON.stringify({spec:1,ready:false,summary:'Ready for a question · save data to begin',findings:[],phases,evaluation:[{method:'tool',by:'the Vega-Lite 6.4.3 schema, compiler and Vega renderer',passed:null,gate:true},{method:'checks',by:'the brief: rows, fields, marks, parameters, assertions',passed:null,gate:true},{method:'review',by:'a chart-reading rubric, by a fresh-context reviewer',passed:null,gate:true,detail:'not run yet'}],updatedAt:new Date().toISOString()},null,2)+'\n');
