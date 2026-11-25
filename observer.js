'use strict';
const $=id=>document.getElementById(id);
const choices=['A','B','BLANCO','NULO'];
const names={A:'Lista A',B:'Lista B',BLANCO:'Voto blanco',NULO:'Voto nulo'};
const colors={A:'#ed3654',B:'#356bc0',BLANCO:'#9ba9bc',NULO:'#39475c'};
let client=null, snapshot=null, timer=null;
const busy=state=>$('loadingOverlay').classList.toggle('hide',!state);
const errorMsg=message=>{$('loginMsg').textContent=message||''};
const rpc=async(name,args={})=>{const {data,error}=await client.rpc(name,args);if(error)throw new Error(error.message);return data};
async function initialize(){
 $('loginBtn').addEventListener('click',login);
 $('refreshBtn').addEventListener('click',()=>refresh(true));
 $('logoutBtn').addEventListener('click',logout);
 $('observerPassword').addEventListener('keydown',e=>{if(e.key==='Enter')login()});
 if(!window.SB_CONFIG||!window.supabase||!SB_CONFIG.supabaseUrl?.startsWith('https://')||!SB_CONFIG.supabaseKey){errorMsg('Falta configurar Supabase mediante config.js');return}
 client=window.supabase.createClient(SB_CONFIG.supabaseUrl,SB_CONFIG.supabaseKey,{auth:{persistSession:true,autoRefreshToken:true}});
 try{let {data:{session}}=await client.auth.getSession();if(session)await enter()}catch(e){errorMsg('No se pudo conectar: '+e.message)}
}
async function login(){const email=$('observerEmail').value.trim(),password=$('observerPassword').value;if(!email||!password){errorMsg('Ingresa correo y contraseña.');return}try{busy(true);const {error}=await client.auth.signInWithPassword({email,password});if(error)throw error;await enter()}catch(e){errorMsg('No se pudo acceder: '+e.message);await client.auth.signOut()}finally{busy(false)}}
async function enter(){try{await refresh(false);$('observerLogin').classList.add('hide');$('observerPanel').classList.remove('hide');$('observerPassword').value='';errorMsg('');if(timer)clearInterval(timer);timer=setInterval(()=>{if(!document.hidden&&snapshot)refresh(false).catch(console.error)},20000)}catch(e){$('observerLogin').classList.remove('hide');$('observerPanel').classList.add('hide');errorMsg('Cuenta sin permisos de observación o error de conexión: '+e.message);await client.auth.signOut()}}
async function logout(){if(timer)clearInterval(timer);timer=null;await client.auth.signOut();snapshot=null;$('observerPanel').classList.add('hide');$('observerLogin').classList.remove('hide');$('electionStatus').textContent='Acceso restringido';$('electionStatus').className='status'}
async function refresh(showAlert=false){try{if(showAlert)busy(true);snapshot=await rpc('sb_observer_snapshot');render()}catch(e){if(showAlert)alert('No se pudo actualizar: '+e.message);else throw e}finally{if(showAlert)busy(false)}}
function render(){const s=snapshot;if(!s)return;const votes=Object.fromEntries(choices.map(k=>[k,Number(s.results?.[k]||0)]));const total=choices.reduce((n,k)=>n+votes[k],0);const valid=votes.A+votes.B;const leading=valid===0?'Sin votos válidos':votes.A===votes.B?'Empate':votes.A>votes.B?'Lista A':'Lista B';const isOpen=Boolean(s.open);
 $('electionStatus').textContent=isOpen?'● ELECCIÓN ABIERTA':'● ELECCIÓN CERRADA';$('electionStatus').className='status'+(isOpen?' open':'');
 $('stats').innerHTML=`<div class="stat"><div class="icon">🗳️</div><div class="number">${total}</div><div class="label">Votos registrados</div></div><div class="stat"><div class="icon">✅</div><div class="number">${valid}</div><div class="label">Votos válidos</div></div><div class="stat"><div class="icon">◯</div><div class="number">${votes.BLANCO+votes.NULO}</div><div class="label">Blancos y nulos</div></div><div class="stat"><div class="icon">📊</div><div class="number" style="font-size:clamp(18px,2vw,24px)">${leading}</div><div class="label">${isOpen?'Encabeza el conteo':'Mayor votación'}</div></div>`;
 $('phaseMessage').textContent=isOpen?'RESULTADOS PRELIMINARES · La elección está abierta. Las cifras aún pueden variar.':'RESULTADOS FINALES · Elección cerrada. Cifras sujetas a validación institucional.';
 $('resultHeading').textContent=isOpen?'Escrutinio preliminar':'Escrutinio final';
 $('resultsArea').innerHTML=choices.map(k=>{const pct=total?votes[k]*100/total:0;return `<div class="vote-row"><div class="vote-top"><span class="vote-name">${names[k]}</span><span class="vote-num">${votes[k]} votos · ${pct.toFixed(1)}%</span></div><div class="track"><div class="fill" style="width:${pct}%;background:${colors[k]}"></div></div></div>`}).join('');
 let cumulative=0;const stops=choices.map(k=>{let start=cumulative;cumulative+=total?votes[k]*100/total:0;return `${colors[k]} ${start}% ${cumulative}%`}).join(',');
 $('donutArea').innerHTML=`<div class="donut" style="background:${total?'conic-gradient('+stops+')':'#e5eaf3'}"><div class="donut-inner"><strong>${total}</strong><span>votos totales</span></div></div>`;
 $('legendArea').innerHTML=choices.map(k=>`<div><i style="background:${colors[k]}"></i>${names[k]}</div>`).join('');
 $('updatedAt').textContent='Actualizado: '+new Date().toLocaleTimeString('es-EC',{hour:'2-digit',minute:'2-digit',second:'2-digit'})+' · Actualización automática cada 20 segundos';
}
window.addEventListener('DOMContentLoaded',initialize);
