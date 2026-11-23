"use strict";
const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const labels={A:'LISTA A',B:'LISTA B',BLANCO:'VOTO BLANCO',NULO:'VOTO NULO'};
let client=null, snapshot=null, currentCourse='Todos';
function msg(value){$('loginMsg').textContent=value||'';}
function busy(v){$('loadingOverlay').classList.toggle('hide',!v)}
async function rpc(name,args={}){const {data,error}=await client.rpc(name,args);if(error)throw new Error(error.message);return data}
async function initialize(){
 $('loginBtn').addEventListener('click',login);
 $('refreshBtn').addEventListener('click',refresh);
 $('logoutBtn').addEventListener('click',logout);
 $('rosterSearch').addEventListener('input',renderRoster);
 $('statusFilter').addEventListener('change',renderRoster);
 if(!window.SB_CONFIG||!window.supabase||!SB_CONFIG.supabaseUrl?.startsWith('https://')||SB_CONFIG.supabaseUrl.includes('TU-PROYECTO')||SB_CONFIG.supabaseKey?.includes('TU_CLAVE')){msg('Configura config.js con los datos públicos de Supabase.');return}
 client=window.supabase.createClient(SB_CONFIG.supabaseUrl,SB_CONFIG.supabaseKey,{auth:{persistSession:true,autoRefreshToken:true}});
 const {data:{session}}=await client.auth.getSession();
 if(session)await enter();
}
async function login(){const email=$('observerEmail').value.trim(),password=$('observerPassword').value;if(!email||!password){msg('Ingresa correo y contraseña.');return}try{busy(true);const {error}=await client.auth.signInWithPassword({email,password});if(error)throw error;await enter()}catch(e){msg('No se pudo acceder: '+e.message);await client.auth.signOut()}finally{busy(false)}}
async function enter(){try{await refresh();$('observerLogin').classList.add('hide');$('observerPanel').classList.remove('hide');$('observerPassword').value='';msg('')}catch(e){$('observerLogin').classList.remove('hide');$('observerPanel').classList.add('hide');msg('La cuenta no tiene permiso de observación o la conexión falló: '+e.message);await client.auth.signOut()}}
async function logout(){await client.auth.signOut();snapshot=null;$('observerPanel').classList.add('hide');$('observerLogin').classList.remove('hide');$('electionStatus').textContent='Acceso restringido'}
async function refresh(){try{busy(true);snapshot=await rpc('sb_observer_snapshot');render()}catch(e){if(snapshot)alert('No fue posible actualizar: '+e.message);else throw e}finally{busy(false)}}
function render(){const s=snapshot;if(!s)return;const rr=s.roster||[];const total=rr.length,done=rr.filter(x=>x.voted).length,pct=total?100*done/total:0;
 $('electionStatus').textContent=s.open?'● ELECCIÓN ABIERTA':'● ELECCIÓN CERRADA';
 $('stats').innerHTML=[['Empadronados',total],['Votaron',done],['Pendientes',total-done],['Participación',pct.toFixed(1)+'%']].map(([k,v])=>`<div class="stat"><strong>${v}</strong><small>${k}</small></div>`).join('');
 $('phaseMessage').textContent=s.open?'ESCRUTINIO PRELIMINAR · Resultados sujetos a cambios hasta el cierre.':'ESCRUTINIO FINAL · Elección cerrada. Los resultados requieren validación y firma institucional.';
 const courses=[...new Set(rr.map(x=>x.course))].sort((a,b)=>a.localeCompare(b,'es'));
 $('courseStats').innerHTML=courses.length?courses.map(c=>{const x=rr.filter(y=>y.course===c),v=x.filter(y=>y.voted).length;return `<div class="course-bar"><span>${esc(c)}</span><div class="track"><div class="fill" style="width:${100*v/x.length}%"></div></div><b>${v}/${x.length}</b></div>`}).join(''):'<p class="muted">El padrón no contiene estudiantes.</p>';
 const votes=Object.fromEntries(Object.keys(labels).map(k=>[k,Number(s.results?.[k]||0)]));const sum=Object.values(votes).reduce((a,b)=>a+b,0);
 $('resultHeading').textContent=s.open?'Resultados preliminares':'Resultados finales';
 $('resultsArea').innerHTML=`<div class="stats">${Object.entries(votes).map(([k,n])=>`<div class="stat"><strong>${n}</strong><small>${labels[k]}</small></div>`).join('')}</div>${Object.entries(votes).map(([k,n])=>`<div class="bar-row"><b>${labels[k]}</b><div class="track"><div class="fill" style="width:${sum?100*n/sum:0}%"></div></div><b>${sum?(100*n/sum).toFixed(1):'0.0'}%</b></div>`).join('')}<p class="muted">Total de votos contabilizados: ${sum}.</p>`;
 renderRoster();
}
function renderRoster(){if(!snapshot)return;const rr=snapshot.roster||[],courses=['Todos',...[...new Set(rr.map(x=>x.course))].sort((a,b)=>a.localeCompare(b,'es'))];if(!courses.includes(currentCourse))currentCourse='Todos';
 $('courseMenu').innerHTML=courses.map(c=>`<button class="${c===currentCourse?'active':''}" data-course="${esc(c)}">${esc(c)} (${c==='Todos'?rr.length:rr.filter(x=>x.course===c).length})</button>`).join('');
 $('courseMenu').querySelectorAll('button').forEach(b=>b.addEventListener('click',()=>{currentCourse=b.dataset.course;renderRoster()}));
 const q=$('rosterSearch').value.trim().toLowerCase(),filter=$('statusFilter').value;
 $('rosterBody').innerHTML=rr.filter(x=>(currentCourse==='Todos'||x.course===currentCourse)&&(filter==='all'||(filter==='yes'&&x.voted)||(filter==='no'&&!x.voted))&&(x.name.toLowerCase().includes(q)||x.id.toLowerCase().includes(q))).map(x=>`<tr><td>${esc(x.id)}</td><td>${esc(x.name)}</td><td>${esc(x.course)}</td><td><span class="status ${x.voted?'':'pending'}">${x.voted?'Votó':'Pendiente'}</span></td></tr>`).join('')||'<tr><td colspan="4">No hay coincidencias.</td></tr>';
}
window.addEventListener('DOMContentLoaded',initialize);
