/* pguard admin shell — renders sidebar+topbar from window.PAGE, wires toggles + helpers */
(function(){
  const MARK = (s)=>`<svg width="${s}" height="${s*1.04}" viewBox="0 0 100 106" fill="none"><defs><linearGradient id="pgm${s}" x1="50" y1="4" x2="50" y2="106" gradientUnits="userSpaceOnUse"><stop stop-color="#1FA971"/><stop offset="1" stop-color="#0E3B2E"/></linearGradient></defs><path d="M50 4 L88 18 V50 C88 78 72 95 50 104 C28 95 12 78 12 50 V18 Z" fill="url(#pgm${s})"/><path d="M50 30 C41 30 34 37 34 46 C34 58 50 74 50 74 C50 74 66 58 66 46 C66 37 59 30 50 30 Z" fill="#fff"/><circle cx="50" cy="46" r="7.5" fill="#1FA971"/></svg>`;
  const I = {
    dash:'<path d="M3 13h8V3H3zM13 21h8V3h-8zM3 21h8v-6H3z"/>',
    map:'<path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
    users:'<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/>',
    shield:'<path d="M12 2l8 3v6c0 5-3.5 8-8 11-4.5-3-8-6-8-11V5z"/>',
    cust:'<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
    star:'<path d="M12 2l3 6 6 1-4.5 4 1 6-5.5-3-5.5 3 1-6L3 9l6-1z"/>',
    wallet:'<rect x="2" y="6" width="20" height="14" rx="3"/><path d="M2 10h20M16 14h2"/>',
    tag:'<path d="M3 3h7l11 11-7 7L3 10z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
    jobs:'<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M8 4v16"/>',
    recruit:'<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M19 8v6M22 11h-6"/>',
    report:'<path d="M3 3v18h18"/><path d="M7 14l4-4 3 3 5-6"/>',
    rules:'<path d="M9 3H5a2 2 0 0 0-2 2v4M21 9V5a2 2 0 0 0-2-2h-4M3 15v4a2 2 0 0 0 2 2h4M15 21h4a2 2 0 0 0 2-2v-4"/>',
    log:'<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M9 13h6M9 17h4"/>',
    settings:'<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M5 5l2 2M17 17l2 2M2 12h3M19 12h3M5 19l2-2M17 7l2-2"/>',
    send:'<path d="M22 2 11 13M22 2l-7 20-4-9-9-4z"/>',
    route:'<circle cx="6" cy="19" r="3"/><circle cx="18" cy="5" r="3"/><path d="M9 19h6a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h3"/>',
    pulse:'<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    tasks:'<path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>',
    call:'<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3-8.6A2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8.1 9.9a16 16 0 0 0 6 6l1.4-1.2a2 2 0 0 1 2.1-.5c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>',
    chatic:'<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
    alert:'<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
    profile:'<circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/>',
  };
  const NAV = [
    {g:'ภาพรวม',ge:'Overview'},
    {k:'dash',ic:'dash',th:'แดชบอร์ด',en:'Dashboard',href:'Admin - Dashboard.html'},
    {k:'operations',ic:'pulse',th:'ปฏิบัติการสด',en:'Operations',href:'Admin - Operations.html',count:'21'},
    {k:'map',ic:'map',th:'แผนที่สด',en:'Live Map',href:'Web Admin Live Map.html'},
    {k:'applicants',ic:'users',th:'ผู้สมัคร',en:'Applicants',href:'Admin - Applicants.html',count:'12'},
    {k:'guards',ic:'shield',th:'พนักงาน รปภ.',en:'Guards',href:'Admin - Guards.html',count:'384'},
    {k:'customers',ic:'cust',th:'ลูกค้า',en:'Customers',href:'Admin - Customers.html'},
    {k:'reviews',ic:'star',th:'รีวิว',en:'Reviews',href:'Admin - Reviews.html',dot:true},
    {g:'การเงิน & งาน',ge:'Finance & Jobs'},
    {k:'tasks',ic:'tasks',th:'จัดการงานทั้งหมด',en:'Tasks',href:'Admin - Tasks.html',count:'48'},
    {k:'bookings',ic:'jobs',th:'จัดการงาน',en:'Bookings',href:'Admin - Bookings.html',count:'27'},
    {k:'wallet',ic:'wallet',th:'กระเป๋าเงิน',en:'Wallet',href:'Admin - Wallet.html',count:'5'},
    {k:'pricing',ic:'tag',th:'กำหนดราคา',en:'Pricing',href:'Admin - Pricing.html'},
    {g:'การสื่อสาร',ge:'Comms'},
    {k:'calls',ic:'call',th:'บันทึกการโทร',en:'Call Logs',href:'Admin - Calls.html'},
    {k:'chat',ic:'chatic',th:'ตรวจสอบแชต',en:'Chat Moderation',href:'Admin - Chat.html'},
    {k:'broadcast',ic:'send',th:'ส่งการแจ้งเตือน',en:'Broadcast',href:'Admin - Broadcast.html'},
    {g:'ระบบ',ge:'System'},
    {k:'expiring',ic:'alert',th:'เอกสารใกล้หมดอายุ',en:'Doc Expiry',href:'Admin - Expiring.html',count:'7'},
    {k:'recruit',ic:'recruit',th:'สรรหาบุคลากร',en:'Recruitment',href:'Admin - Recruitment.html'},
    {k:'reports',ic:'report',th:'รายงาน',en:'Reports',href:'Admin - Reports.html'},
    {k:'automation',ic:'rules',th:'กฎอัตโนมัติ',en:'Automation',href:'Admin - Automation.html'},
    {k:'replay',ic:'route',th:'ดูเส้นทางย้อนหลัง',en:'Location Replay',href:'Admin - Location Replay.html'},
    {k:'log',ic:'log',th:'Activity Log',en:'Activity Log',href:'Admin - Activity Log.html'},
    {k:'settings',ic:'settings',th:'ตั้งค่า',en:'Settings',href:'Admin - Settings.html'},
    {k:'profile',ic:'profile',th:'โปรไฟล์ผู้ดูแล',en:'Admin Profile',href:'Admin - Profile.html'},
  ];

  const P = window.PAGE || {};
  function navHTML(it){
    if(it.g) return `<div class="nav-group-label" data-th>${it.g}</div><div class="nav-group-label" data-en lang-hide>${it.ge}</div>`;
    const on = it.k===P.active;
    let right = it.dot ? '<span class="badge-dot"></span>' : (it.count ? `<span class="count">${it.count}</span>`:'');
    return `<a class="nav ${on?'on':''}" href="${it.href}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${I[it.ic]}</svg><span data-th>${it.th}</span><span data-en lang-hide>${it.en}</span>${right}</a>`;
  }

  function build(){
    const side = document.getElementById('pgSide');
    if(side) side.innerHTML = `
      <div class="side-top">${MARK(28)}<span class="wm"><span class="p">p</span>guard</span></div>
      <div class="side-scroll">${NAV.map(navHTML).join('')}</div>
      <div class="side-foot">
        <div class="avatar">วร</div>
        <div style="flex:1;min-width:0"><div style="font-size:13px;font-weight:600;color:var(--text-strong)">วรรณา ร.</div><div style="font-size:11px;color:var(--text-muted)">Operations Lead</div></div>
        <div class="seg-mini" id="pgTheme"><button data-set="light">☀</button><button data-set="dark">☾</button></div>
      </div>`;
    const top = document.getElementById('pgTop');
    if(top) top.innerHTML = `
      <div><h1><span data-th>${P.title||''}</span><span data-en lang-hide>${P.titleEn||P.title||''}</span></h1>
      ${P.sub?`<div class="sub"><span data-th>${P.sub}</span><span data-en lang-hide>${P.subEn||P.sub}</span></div>`:''}</div>
      <div style="flex:1"></div>
      <div class="search"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg><input placeholder="ค้นหา…"></div>
      <button class="icon-btn"><span class="ndot"></span><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/></svg></button>
      <div class="seg-mini" id="pgLang"><button data-l="th">ไทย</button><button data-l="en">EN</button></div>
      <div class="usermenu" id="pgUser">
        <button class="um-trigger"><span class="um-av">วร</span><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m6 9 6 6 6-6"/></svg></button>
        <div class="um-pop">
          <div class="um-head"><div class="um-av lg">วร</div><div><div class="um-nm">วรรณา รักดี</div><div class="um-role">Operations Lead · admin@pguard.co.th</div></div></div>
          <a class="um-item"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/></svg><span data-th>โปรไฟล์ของฉัน</span><span data-en lang-hide>My profile</span></a>
          <a class="um-item" href="Admin - Settings.html"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></svg><span data-th>ตั้งค่า</span><span data-en lang-hide>Settings</span></a>
          <div class="um-div"></div>
          <a class="um-item danger" onclick="pg.open('#pgLogout')"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg><span data-th>ลงชื่อออก</span><span data-en lang-hide>Log out</span></a>
        </div>
      </div>`;

    // theme
    const theme = localStorage.getItem('pg_theme')||'light';
    setTheme(theme);
    document.getElementById('pgTheme')?.addEventListener('click',e=>{const b=e.target.closest('button');if(b)setTheme(b.dataset.set);});
    // lang
    const lang = localStorage.getItem('pg_lang')||'th';
    setLang(lang);
    document.getElementById('pgLang')?.addEventListener('click',e=>{const b=e.target.closest('button');if(b)setLang(b.dataset.l);});
    // user menu
    const um=document.getElementById('pgUser');
    um?.querySelector('.um-trigger')?.addEventListener('click',e=>{e.stopPropagation();um.classList.toggle('open');});
    document.addEventListener('click',()=>um?.classList.remove('open'));
    // logout confirm dialog (injected once)
    if(!document.getElementById('pgLogout')){
      const d=document.createElement('div'); d.className='overlay'; d.id='pgLogout';
      d.innerHTML=`<div class="modal" style="width:380px"><div class="modal-body" style="text-align:center;padding:28px 24px">
        <div style="width:56px;height:56px;border-radius:50%;background:var(--danger-bg);color:var(--danger);display:flex;align-items:center;justify-content:center;margin:0 auto 16px"><svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg></div>
        <div style="font-size:18px;font-weight:600;color:var(--text-strong);margin-bottom:6px"><span data-th>ออกจากระบบ?</span><span data-en lang-hide>Log out?</span></div>
        <div style="font-size:13.5px;color:var(--text-muted);line-height:1.5"><span data-th>เซสชันบนเซิร์ฟเวอร์จะถูกยกเลิกและคุณต้องเข้าสู่ระบบใหม่</span><span data-en lang-hide>Your server session will be revoked and you'll need to sign in again.</span></div></div>
        <div class="modal-foot"><button class="btn secondary" onclick="pg.close('#pgLogout')"><span data-th>ยกเลิก</span><span data-en lang-hide>Cancel</span></button><button class="btn danger" onclick="pg.close('#pgLogout');pg.toast('ออกจากระบบแล้ว',false)"><span data-th>ลงชื่อออก</span><span data-en lang-hide>Log out</span></button></div></div>`;
      document.body.appendChild(d);
    }
  }
  function setTheme(t){
    document.documentElement.setAttribute('data-theme',t); localStorage.setItem('pg_theme',t);
    document.querySelectorAll('#pgTheme button').forEach(b=>b.classList.toggle('on',b.dataset.set===t));
  }
  function setLang(l){
    localStorage.setItem('pg_lang',l); document.documentElement.lang=l;
    document.querySelectorAll('#pgLang button').forEach(b=>b.classList.toggle('on',b.dataset.l===l));
    document.querySelectorAll('[data-th]').forEach(el=>el.toggleAttribute('lang-hide', l!=='th'));
    document.querySelectorAll('[data-en]').forEach(el=>el.toggleAttribute('lang-hide', l!=='en'));
  }

  // ---- helpers ----
  window.pg = {
    open:(sel)=>document.querySelector(sel)?.classList.add('show'),
    close:(sel)=>document.querySelector(sel)?.classList.remove('show'),
    setLang, setTheme,
    toast:(msg, ok=true)=>{
      let w=document.querySelector('.toast-wrap'); if(!w){w=document.createElement('div');w.className='toast-wrap';document.body.appendChild(w);}
      const t=document.createElement('div'); t.className='toast';
      t.innerHTML=`<span class="ti" style="background:${ok?'var(--success)':'var(--danger)'}"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3"><path d="${ok?'M20 6 9 17l-5-5':'M18 6 6 18M6 6l12 12'}"/></svg></span>${msg}`;
      w.appendChild(t); setTimeout(()=>{t.style.opacity='0';t.style.transition='.3s';setTimeout(()=>t.remove(),300);},2600);
    },
    relabel:()=>setLang(localStorage.getItem('pg_lang')||'th'),
  };

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',build); else build();
})();
