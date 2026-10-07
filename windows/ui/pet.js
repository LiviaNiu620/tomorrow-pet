'use strict';
document.getElementById('open-main').addEventListener('click',()=>window.dango.openMain());
function show(state){const f=state.focus;document.getElementById('pet-text').textContent=f?.status==='running'?`专注中 · ${Math.ceil(Math.max(0,f.endsAt-Date.now())/60000)} 分钟`:'一天一串，慢慢吃完。';}
window.dango.onState(show);window.dango.load().then(r=>{if(r.ok)show(r.value);});
