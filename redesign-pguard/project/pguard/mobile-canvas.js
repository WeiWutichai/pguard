/* pguard mobile canvas — theme+lang toolbar + helpers */
(function(){
  const tb=document.createElement('div'); tb.className='mtoolbar';
  tb.innerHTML=`<div class="mseg" id="mLang"><button data-l="th">ไทย</button><button data-l="en">EN</button></div>
    <div class="mseg" id="mTheme"><button data-set="light">☀ Light</button><button data-set="dark">☾ Dark</button></div>`;
  document.body.appendChild(tb);
  function setTheme(t){document.documentElement.setAttribute('data-theme',t);localStorage.setItem('pg_theme',t);document.querySelectorAll('#mTheme button').forEach(b=>b.classList.toggle('on',b.dataset.set===t));}
  function setLang(l){localStorage.setItem('pg_lang',l);document.documentElement.lang=l;document.querySelectorAll('#mLang button').forEach(b=>b.classList.toggle('on',b.dataset.l===l));
    document.querySelectorAll('[data-th]').forEach(el=>el.toggleAttribute('lang-hide',l!=='th'));
    document.querySelectorAll('[data-en]').forEach(el=>el.toggleAttribute('lang-hide',l!=='en'));}
  setTheme(localStorage.getItem('pg_theme')||'light');
  setLang(localStorage.getItem('pg_lang')||'th');
  document.getElementById('mTheme').addEventListener('click',e=>{const b=e.target.closest('button');if(b)setTheme(b.dataset.set);});
  document.getElementById('mLang').addEventListener('click',e=>{const b=e.target.closest('button');if(b)setLang(b.dataset.l);});
  window.pgRelabel=()=>setLang(localStorage.getItem('pg_lang')||'th');
})();
