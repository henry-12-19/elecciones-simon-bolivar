"use strict";
const $ = id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const labels={A:'LISTA A',B:'LISTA B',BLANCO:'VOTO BLANCO',NULO:'VOTO NULO'};
const placeholder=l=>`data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="150" height="150"><rect width="150" height="150" rx="28" fill="${l==='A'?'#e83c58':'#2d55a7'}"/><circle cx="75" cy="55" r="23" fill="#ffffffbb"/><path d="M26 135q5-46 49-46t49 46" fill="#ffffffbb"/></svg>`)}`;
const profilesDefault={A:{name:'Representante Lista A',slogan:'Propuesta estudiantil A',photo:'',logo:''},B:{name:'Representante Lista B',slogan:'Propuesta estudiantil B',photo:'',logo:''}};
let client=null,publicConfig=null,selected=null,voter=null,working=false;
function msg(id,value,good=false){$(id).innerHTML=value?`<div class="alert ${good?'good':''}">${esc(value)}</div>`:''}
function busy(value){working=value;$('loadingOverlay').classList.toggle('hide',!value)}
async function rpc(name,args={}){if(!client)throw Error('Sistema no conectado. Revisa config.js.');const {data,error}=await client.rpc(name,args);if(error)throw Error(error.message);return data}
async function bootstrap(){if(!window.SB_CONFIG||!window.supabase||!SB_CONFIG.supabaseUrl.startsWith('https://')||SB_CONFIG.supabaseUrl.includes('TU-PROYECTO')||SB_CONFIG.supabaseKey.includes('TU_CLAVE')){$('electionStatus').textContent='Pendiente de configuración';msg('identifyMsg','Configura config.js para conectar Supabase.');return;}try{client=window.supabase.createClient(SB_CONFIG.supabaseUrl,SB_CONFIG.supabaseKey,{auth:{persistSession:false,autoRefreshToken:false}});await refreshConfig()}catch(e){msg('identifyMsg','No se pudo conectar: '+e.message)}}
async function refreshConfig(){publicConfig=await rpc('sb_public_config');$('electionStatus').textContent=publicConfig.is_open?'● Elección abierta':'● Elección cerrada';for(const l of ['A','B']){const p=publicConfig.profiles?.[l]||profilesDefault[l];$('photo'+l).src=p.photo||placeholder(l);$('logo'+l).src=p.logo||placeholder(l);$('name'+l).textContent=p.name||profilesDefault[l].name;$('slogan'+l).textContent=p.slogan||''}return publicConfig}
function step(n){for(const name of ['Identify','Ballot','Confirm','Success'])$('step'+name).classList.toggle('hide',name!==n);window.scrollTo({top:0,behavior:'smooth'})}
async function verifyStudent(){const id=$('voterId').value.trim();if(!id){msg('identifyMsg','Ingresa tu cédula o matrícula.');return}try{busy(true);await refreshConfig();const r=await rpc('sb_verify',{p_id:id});if(!r?.ok){msg('identifyMsg',r?.message||'No fue posible verificar.');return;}voter={id,name:r.name,course:r.course};$('verifiedStudent').textContent=`${r.name} · ${r.course}`;msg('identifyMsg','');selected=null;renderSelection();step('Ballot')}catch(e){msg('identifyMsg',e.message)}finally{busy(false)}}
function selectChoice(choice){selected=choice;renderSelection()}
function renderSelection(){document.querySelectorAll('.choice').forEach(c=>c.classList.toggle('selected',c.dataset.choice===selected));$('ballotChoices').classList.toggle('has-selection',!!selected);$('continueButton').disabled=!selected}
function showConfirm(){if(!selected||!voter)return;$('confirmChoice').textContent=labels[selected];msg('voteMsg','');step('Confirm')}
function backToChoices(){step('Ballot')}
function goBack(){selected=null;voter=null;step('Identify')}
async function submitBallot(){if(!voter||!selected||working)return;try{busy(true);const result=await rpc('sb_cast_vote',{p_id:voter.id,p_choice:selected});if(!result?.ok){msg('voteMsg',result?.message||'No se pudo registrar el voto.');return;}voter=null;selected=null;$('voterId').value='';step('Success')}catch(e){msg('voteMsg',e.message)}finally{busy(false)}}
function resetVoter(){voter=null;selected=null;renderSelection();step('Identify')}
window.addEventListener("DOMContentLoaded",bootstrap);
