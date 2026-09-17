// Studio chart themes, shared by the pane (classic script) and the toolchain exports (CommonJS).
// The theme sits beneath the author's config. In dark mode, chrome colours chosen for paper
// (backgrounds, title/axis/legend text, grid lines, text labels) are swapped for legible ones;
// data colours are never touched.
(function(root){
  const FONT='-apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif';
  const PALETTES={
    light:{background:'#ffffff',title:'#183d32',subtitle:'#62746c',label:'#55665f',axisTitle:'#344a43',grid:'#e8eeea',domain:'#c5d0ca',view:'#e3e9e5',text:'#29443a',rule:'#6d7d76',brush:'#203b32',brushStroke:'#203b32'},
    dark:{background:'#1b2925',title:'#eef4ee',subtitle:'#9db3a6',label:'#a7bbaf',axisTitle:'#cddbd1',grid:'#2a3d35',domain:'#456054',view:'#34493f',text:'#dce7de',rule:'#9fb5a8',brush:'#dce7de',brushStroke:'#eef4ee'}
  };
  const isObject=v=>!!v && typeof v==='object' && !Array.isArray(v);
  function merge(base,over){if(!isObject(base)||!isObject(over))return over===undefined?base:over;const out={...base};for(const [k,v] of Object.entries(over))out[k]=isObject(v)&&isObject(base[k])?merge(base[k],v):v;return out;}
  function config(mode){
    const p=PALETTES[mode]||PALETTES.light;
    return {
      background:p.background,font:FONT,
      title:{color:p.title,subtitleColor:p.subtitle,anchor:'start',fontSize:18,fontWeight:600,subtitleFontSize:13,subtitlePadding:5,offset:14},
      axis:{labelColor:p.label,titleColor:p.axisTitle,gridColor:p.grid,domainColor:p.domain,tickColor:p.domain,labelFontSize:11,titleFontSize:12,titleFontWeight:600,titlePadding:8},
      legend:{labelColor:p.label,titleColor:p.axisTitle,labelFontSize:12,titleFontSize:12,titleFontWeight:600},
      header:{labelColor:p.axisTitle,titleColor:p.title,labelFontSize:12,titleFontSize:13},
      view:{stroke:p.view},text:{color:p.text},rule:{color:p.rule},
      selection:{interval:{mark:{fill:p.brush,fillOpacity:mode==='dark'?.16:.1,stroke:p.brushStroke,strokeOpacity:.5}}}
    };
  }
  const NAMED={black:[0,0,0],white:[255,255,255],gray:[128,128,128],grey:[128,128,128],dimgray:[105,105,105],darkgray:[169,169,169],lightgray:[211,211,211],silver:[192,192,192],whitesmoke:[245,245,245],gainsboro:[220,220,220]};
  function luminance(color){
    if(typeof color!=='string')return null;const c=color.trim().toLowerCase();let rgb=NAMED[c];
    if(!rgb&&/^#[0-9a-f]{3,8}$/.test(c)){const h=c.length<6?c.slice(1,4).split('').map(x=>x+x).join(''):c.slice(1,7);rgb=[0,2,4].map(i=>parseInt(h.slice(i,i+2),16));}
    if(!rgb){const m=c.match(/^rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)/);if(m)rgb=m.slice(1,4).map(Number);}
    if(!rgb||rgb.some(Number.isNaN))return null;
    const [r,g,b]=rgb.map(v=>{v/=255;return v<=.03928?v/12.92:Math.pow((v+.055)/1.055,2.4);});return .2126*r+.7152*g+.0722*b;
  }
  // Dark mode only: replace a literal when it was drawn for paper.
  const tooDark=v=>{const l=luminance(v);return l!==null&&l<.3;};
  const tooLight=v=>{const l=luminance(v);return l!==null&&l>.35;};
  const nearBlack=v=>{const l=luminance(v);return l!==null&&l<.02;};
  function adaptDark(node,p,parentKey,unitMark){
    if(Array.isArray(node)){node.forEach(x=>adaptDark(x,p,parentKey,null));return;}
    if(!isObject(node))return;
    const ownMark=typeof node.mark==='string'?node.mark:node.mark?.type;
    for(const [k,v] of Object.entries(node)){
      if(k==='values'||k==='datasets'||k==='data')continue;
      if((k==='labelColor'||k==='titleColor')&&tooDark(v))node[k]=k==='labelColor'?p.label:p.axisTitle;
      else if(k==='subtitleColor'&&tooDark(v))node[k]=p.subtitle;
      else if((k==='gridColor'||k==='domainColor'||k==='tickColor')&&typeof v==='string')node[k]=k==='gridColor'?p.grid:p.domain;
      else if(k==='background'&&tooLight(v))node[k]=p.background;
      else if(k==='color'&&parentKey==='title'&&tooDark(v))node[k]=p.title;
      else if(parentKey==='view'&&k==='stroke'&&typeof v==='string')node[k]=p.view;
      else if(parentKey==='view'&&k==='fill'&&tooLight(v))node[k]=p.background;
      else if(parentKey==='legend'&&k==='fillColor'&&tooLight(v))node[k]=p.background;
      else if((parentKey==='text'||unitMark==='text')&&(k==='color'||k==='fill')&&tooDark(v))node[k]=p.text;
      else if((parentKey==='rule'||unitMark==='rule')&&(k==='color'||k==='stroke')&&nearBlack(v))node[k]=p.rule;
      else if(isObject(v)||Array.isArray(v))adaptDark(v,p,k,k==='mark'?ownMark:null);
    }
    // A text label's constant colour, e.g. "encoding": {"color": {"value": "#333"}}.
    const constant=node.encoding?.color;
    if(ownMark==='text'&&isObject(constant)&&tooDark(constant.value))constant.value=p.text;
  }
  // A copy of the authored spec, ready to embed or export in the given mode. The authored config wins over the theme.
  function themed(spec,mode){
    const out=JSON.parse(JSON.stringify(spec));const dark=mode==='dark';
    out.config=merge(config(mode),out.config||{});
    if(dark)adaptDark(out,PALETTES.dark,'',null);
    return out;
  }
  const api={config,themed,luminance,PALETTES};
  if(typeof module==='object'&&module.exports)module.exports=api;else root.VegaLiteStudioTheme=api;
})(typeof globalThis!=='undefined'?globalThis:this);
