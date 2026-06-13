/* Utilidades compartidas por index.html, admin.html y validador.html */

let sb = null;

function isConfigured(){
  return SUPABASE_URL && !SUPABASE_URL.includes("TU-PROYECTO") && SUPABASE_KEY && !SUPABASE_KEY.includes("TU-ANON");
}

function initSupabase(){
  if(isConfigured()){
    sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
  } else {
    const warn=document.getElementById('cfgWarn');
    if(warn) warn.classList.remove('hidden');
  }
  return sb;
}

function msg(id,txt,tipo){ document.getElementById(id).innerHTML=`<div class="alert ${tipo}">${txt}</div>`; }

function togglePasswordField(inputId,btnId){
  const inp=document.getElementById(inputId);
  const btn=document.getElementById(btnId);
  if(inp.type==='password'){ inp.type='text'; btn.textContent='🙈'; }
  else{ inp.type='password'; btn.textContent='👁️'; }
}

// Las funciones RPC de Supabase que devuelven una fila (no setof) llegan
// como un arreglo de un elemento ([{...}]); aquí se desempaqueta.
function unwrapRpc(data){
  return Array.isArray(data) ? data[0] : data;
}
