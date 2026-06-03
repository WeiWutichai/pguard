/* pguard prototype — shared parts (icons, map, chrome). Exported to window. */
const { useState, useEffect, useRef } = React;

// ---------- icon set (lucide-style) ----------
const P = (d, k) => React.createElement('path', { d, key:k, fill:'none' });
function Ico({ n, s=22, w=2, c='currentColor', style }) {
  const paths = {
    back:['m15 18-6-6 6-6'], close:['M18 6 6 18','M6 6l12 12'], chevR:['m9 18 6-6-6-6'],
    pin:['M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z','M12 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'],
    shield:['M12 2l8 3v6c0 5-3.5 8-8 11-4.5-3-8-6-8-11V5z'],
    cal:['M3 4h18v18H3z','M16 2v4M8 2v4M3 10h18'],
    users:['M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2','M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8'],
    village:['M3 21h18','M5 21V8l7-5 7 5v13','M9 21v-6h6v6'],
    condo:['M5 3h14v18H5z','M9 7h2M13 7h2M9 11h2M13 11h2M9 15h2M13 15h2'],
    factory:['M2 20h20','M4 20V8l6 3V8l6 3V4l4 2v14'],
    event:['M4 11a9 9 0 0 1 16 0','M2 11h20','M12 4v3'],
    chat:['M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z'],
    phone:['M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3-8.6A2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8.1 9.9a16 16 0 0 0 6 6l1.4-1.2a2 2 0 0 1 2.1-.5c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z'],
    check:['M20 6 9 17l-5-5'], arrow:['M5 12h14','M13 6l6 6-6 6'],
    gps:['M12 12m-3 0a3 3 0 1 0 6 0a3 3 0 1 0-6 0','M12 2v3M12 19v3M2 12h3M19 12h3'],
    star:['M12 2l3 6 6 1-4.5 4 1 6-5.5-3-5.5 3 1-6L3 9l6-1z'],
    cam:['M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z','M12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8'],
    warn:['M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z','M12 9v4','M12 17h.01'],
    promptpay:['M3 5h18v14H3z','M3 10h18','M7 15h4'],
    card:['M2 6h20v12H2z','M2 10h20','M6 14h3'],
    wallet:['M3 6h16a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H3z','M3 10h18','M16 14h2'],
    receipt:['M5 2v20l3-2 3 2 3-2 3 2V2l-3 2-3-2-3 2z','M9 8h6M9 12h6'],
    clock:['M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20','M12 7v5l3 2'],
    badge:['M12 2l2.4 1.8 3-.2.6 2.9 2.4 1.8-1.2 2.7 1.2 2.7-2.4 1.8-.6 2.9-3-.2L12 22l-2.4-1.8-3 .2-.6-2.9L3.6 16l1.2-2.7L3.6 10.6 6 8.8l.6-2.9 3 .2z'],
    nav:['M3 11l19-9-9 19-2-8z'],
  };
  return React.createElement('svg', { width:s, height:s, viewBox:'0 0 24 24', fill:'none',
    stroke:c, strokeWidth:w, strokeLinecap:'round', strokeLinejoin:'round', style },
    (paths[n]||[]).map((d,i)=>P(d,i)));
}

// deterministic pseudo-random for stable map
function mulberry(seed){ return function(){ let t=seed+=0x6D2B79F5; t=Math.imul(t^t>>>15,t|1); t^=t+Math.imul(t^t>>>7,t|61); return ((t^t>>>14)>>>0)/4294967296; }; }

function MapBg(){
  const rnd = mulberry(42);
  let blocks = [];
  for(let y=10;y<700;y+=58){ for(let x=10;x<400;x+=60){
    if(x<150 && y>x*-1.0+560) continue;
    if(rnd()>0.28) blocks.push({x:x+rnd()*8, y:y+rnd()*8, w:44+rnd()*6, h:40+rnd()*6});
  }}
  const W=400,H=700;
  return React.createElement('svg',{className:'bg',viewBox:`0 0 ${W} ${H}`,preserveAspectRatio:'xMidYMid slice'},
    React.createElement('rect',{width:W,height:H,fill:'var(--m-land, #E7ECE7)'}),
    React.createElement('path',{d:`M-30 ${H} L120 ${H} L200 380 L150 180 L40 -20 L-30 -20 Z`,fill:'var(--m-water,#BFE0E8)',opacity:.65}),
    React.createElement('circle',{cx:300,cy:240,r:60,fill:'var(--m-park,#D2E7CC)'}),
    React.createElement('g',{stroke:'var(--m-major,#FBF6E9)',strokeWidth:14,strokeLinecap:'round'},
      React.createElement('line',{x1:0,y1:230,x2:400,y2:270}),
      React.createElement('line',{x1:0,y1:480,x2:400,y2:510}),
      React.createElement('line',{x1:240,y1:0,x2:280,y2:700})),
    React.createElement('g',{stroke:'var(--m-road,#fff)',strokeWidth:6},
      [10,68,126,184,242,300,358].map((y,i)=>React.createElement('line',{key:'h'+i,x1:0,y1:y*1.1+30,x2:400,y2:y*1.1+30})),
      [10,70,130,190,250,310,370].map((x,i)=>React.createElement('line',{key:'v'+i,x1:x,y1:0,x2:x,y2:700}))),
    React.createElement('g',{fill:'var(--m-block,#F2F5F1)',stroke:'var(--m-stroke,#DCE3DB)',strokeWidth:1},
      blocks.map((b,i)=>React.createElement('rect',{key:i,x:b.x,y:b.y,width:b.w,height:b.h,rx:3}))));
}

function MapVars({ dark }){
  // injects map color vars onto the .map element via inline style
  return dark
    ? {'--m-land':'#0C1310','--m-block':'#121C17','--m-road':'#1E2A24','--m-major':'#293A31','--m-water':'#0F2730','--m-park':'#13251A','--m-stroke':'#1A2620'}
    : {};
}

function StatusBar({ onMap }){
  return React.createElement('div',{className:'statusbar'+(onMap?' on-map':'')},
    React.createElement('span',null,'9:41'),
    React.createElement('span',{style:{fontSize:13,letterSpacing:'1px'}},'●●● 5G ▮'));
}

Object.assign(window, { Ico, MapBg, MapVars, StatusBar, useState, useEffect, useRef });
