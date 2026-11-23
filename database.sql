-- SISTEMA ELECTORAL SIMÓN BOLÍVAR · INSTALACIÓN INICIAL
-- Ejecutar en Supabase > SQL Editor en un proyecto NUEVO, no en una BD existente.
-- Requiere pgcrypto (incluido en Supabase). Si se instala en schema extensions, se usa extensions.crypt.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.sb_election (
 id integer primary key default 1 check (id=1),
 title text not null default 'Elecciones del Consejo Estudiantil',
 is_open boolean not null default false,
 opened_at timestamptz,
 closed_at timestamptz,
 profiles jsonb not null default '{"A":{"name":"Representante Lista A","slogan":"Lista A","photo":"","logo":""},"B":{"name":"Representante Lista B","slogan":"Lista B","photo":"","logo":""}}'::jsonb
);
insert into public.sb_election(id) values(1) on conflict(id) do nothing;

create table if not exists public.sb_voters (
 id text primary key check (length(id) between 3 and 24),
 full_name text not null,
 course text not null,
 pin_hash text not null,
 has_voted boolean not null default false
);
create index if not exists sb_voters_course_idx on public.sb_voters(course);

-- Deliberadamente SIN cédula, nombre ni enlace al votante: secreto del voto.
create table if not exists public.sb_ballots (
 ballot_id bigint generated always as identity primary key,
 choice text not null check (choice in ('A','B','BLANCO','NULO')),
 created_at timestamptz not null default now()
);

create table if not exists public.sb_admins (
 user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.sb_admin_audit (
 audit_id bigint generated always as identity primary key,
 actor uuid,
 operation text not null,
 created_at timestamptz not null default now()
);
-- Limitar intentos por identificación, sin registrar las opciones de voto.
create table if not exists public.sb_attempts (
 id text primary key,
 attempts integer not null default 0,
 last_attempt timestamptz not null default now()
);

alter table public.sb_election enable row level security;
alter table public.sb_voters enable row level security;
alter table public.sb_ballots enable row level security;
alter table public.sb_admins enable row level security;
alter table public.sb_admin_audit enable row level security;
alter table public.sb_attempts enable row level security;
revoke all on public.sb_election, public.sb_voters, public.sb_ballots, public.sb_admins, public.sb_admin_audit, public.sb_attempts from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

create or replace function public.sb_is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.sb_admins where user_id = (select auth.uid()));
$$;

create or replace function public.sb_public_config()
returns jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('title',title,'is_open',is_open,'profiles',profiles)
 from public.sb_election where id=1;
$$;

-- La verificación ofrece nombre/curso sólo cuando el PIN es correcto.
create or replace function public.sb_verify(p_id text, p_pin text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.sb_voters%rowtype; a public.sb_attempts%rowtype; opened boolean;
begin
 select is_open into opened from public.sb_election where id=1;
 if not opened then return jsonb_build_object('ok',false,'message','La elección no está abierta.'); end if;
 if p_id is null or length(p_id)>24 or p_pin is null or length(p_pin)>40 then
  return jsonb_build_object('ok',false,'message','Identificación o PIN incorrectos.');
 end if;
 insert into public.sb_attempts(id,attempts,last_attempt) values(p_id,0,now()) on conflict(id) do nothing;
 select * into a from public.sb_attempts where id=p_id for update;
 if a.last_attempt < now() - interval '15 minutes' then
  update public.sb_attempts set attempts=0,last_attempt=now() where id=p_id;
  a.attempts:=0;
 end if;
 if a.attempts >= 5 then return jsonb_build_object('ok',false,'message','Demasiados intentos. Intenta de nuevo en 15 minutos.'); end if;
 select * into v from public.sb_voters where id=p_id;
 if not found or v.pin_hash <> extensions.crypt(p_pin,v.pin_hash) then
  update public.sb_attempts set attempts=attempts+1,last_attempt=now() where id=p_id;
  return jsonb_build_object('ok',false,'message','Identificación o PIN incorrectos.');
 end if;
 if v.has_voted then return jsonb_build_object('ok',false,'message','Esta identificación ya emitió su voto.'); end if;
 return jsonb_build_object('ok',true,'name',v.full_name,'course',v.course);
end; $$;

-- Transacción serializada por fila y validación de PIN de nuevo al votar.
create or replace function public.sb_cast_vote(p_id text,p_pin text,p_choice text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.sb_voters%rowtype; opened boolean; a public.sb_attempts%rowtype;
begin
 if p_choice not in ('A','B','BLANCO','NULO') or p_choice is null then
  return jsonb_build_object('ok',false,'message','Selección no válida.'); end if;
 if p_id is null or length(p_id)>24 or p_pin is null or length(p_pin)>40 then
  return jsonb_build_object('ok',false,'message','Identificación o PIN incorrectos.'); end if;
 -- bloqueo de elección antes del bloqueo de votante; cierre espera esta operación.
 select is_open into opened from public.sb_election where id=1 for share;
 if not opened then return jsonb_build_object('ok',false,'message','La elección está cerrada.'); end if;
 insert into public.sb_attempts(id,attempts,last_attempt) values(p_id,0,now()) on conflict(id) do nothing;
 select * into a from public.sb_attempts where id=p_id for update;
 if a.last_attempt < now() - interval '15 minutes' then
  update public.sb_attempts set attempts=0,last_attempt=now() where id=p_id; a.attempts:=0;
 end if;
 if a.attempts >= 5 then return jsonb_build_object('ok',false,'message','Demasiados intentos. Intenta luego.'); end if;
 select * into v from public.sb_voters where id=p_id for update;
 if not found or v.pin_hash <> extensions.crypt(p_pin,v.pin_hash) then
  update public.sb_attempts set attempts=attempts+1,last_attempt=now() where id=p_id;
  return jsonb_build_object('ok',false,'message','Identificación o PIN incorrectos.');
 end if;
 if v.has_voted then return jsonb_build_object('ok',false,'message','Esta identificación ya votó.'); end if;
 update public.sb_voters set has_voted=true where id=p_id;
 insert into public.sb_ballots(choice) values(p_choice);
 delete from public.sb_attempts where id=p_id;
 return jsonb_build_object('ok',true,'message','Voto registrado correctamente.');
end; $$;

-- Solo el administrador puede obtener estadísticas y padrón.
-- Los votos por lista permanecen ocultos hasta cerrar las elecciones.
create or replace function public.sb_admin_snapshot()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare cfg public.sb_election%rowtype; result jsonb; roster jsonb; voting jsonb;
begin
 if not public.sb_is_admin() then raise exception 'Acceso no autorizado'; end if;
 select * into cfg from public.sb_election where id=1;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name,'course',course,'voted',has_voted) order by course,full_name),'[]'::jsonb) into roster from public.sb_voters;
 select jsonb_build_object('total',(select count(*) from public.sb_voters),'voted',(select count(*) from public.sb_voters where has_voted)) into voting;
 if cfg.is_open then result := null;
 else select coalesce(jsonb_object_agg(choice,n),'{}'::jsonb) into result from
  (select choice,count(*) as n from public.sb_ballots group by choice) x;
 end if;
 return jsonb_build_object('title',cfg.title,'open',cfg.is_open,'profiles',cfg.profiles,'roster',roster,'turnout',voting,'results',result,
 'audit',(select coalesce(jsonb_agg(jsonb_build_object('action',operation,'date',created_at) order by created_at desc),'[]'::jsonb) from (select operation,created_at from public.sb_admin_audit order by audit_id desc limit 30) a));
end; $$;

create or replace function public.sb_set_open(p_open boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if not public.sb_is_admin() then raise exception 'Acceso no autorizado'; end if;
 if p_open and not exists(select 1 from public.sb_voters) then raise exception 'Primero debes cargar estudiantes'; end if;
 update public.sb_election set is_open=p_open,opened_at=case when p_open then now() else opened_at end,
 closed_at=case when p_open then null else now() end where id=1;
 insert into public.sb_admin_audit(actor,operation) values(auth.uid(),case when p_open then 'Elección abierta' else 'Elección cerrada' end);
end; $$;

-- Importación en lotes hasta 300, siempre antes de la apertura y sin votos.
create or replace function public.sb_import_roster(p_rows jsonb, p_replace boolean default false)
returns integer language plpgsql security definer set search_path = '' as $$
declare r jsonb; n integer:=0; ident text; fullname text; grade text; pin text;
begin
 if not public.sb_is_admin() then raise exception 'Acceso no autorizado'; end if;
 if (select is_open from public.sb_election where id=1) or exists(select 1 from public.sb_ballots) then
  raise exception 'Solo puedes importar con elección cerrada y sin votos'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>300 then
  raise exception 'Importa entre 1 y 300 estudiantes por lote'; end if;
 if p_replace then delete from public.sb_voters; end if;
 for r in select value from jsonb_array_elements(p_rows) loop
  ident:=trim(r->>'id');fullname:=trim(r->>'name');grade:=trim(r->>'course');pin:=r->>'pin';
  if ident is null or ident !~ '^[A-Za-z0-9-]{3,24}$' or fullname is null or length(fullname) not between 2 and 120 or
     grade is null or length(grade) not between 1 and 80 or pin is null or length(pin) not between 6 and 40 then
    raise exception 'Datos de padrón inválidos. Todos necesitan PIN de 6 caracteres o más'; end if;
  insert into public.sb_voters(id,full_name,course,pin_hash)
  values(ident,fullname,grade,extensions.crypt(pin,extensions.gen_salt('bf',10)))
  on conflict(id) do update set full_name=excluded.full_name,course=excluded.course,pin_hash=excluded.pin_hash,has_voted=false;
  n:=n+1;
 end loop;
 insert into public.sb_admin_audit(actor,operation) values(auth.uid(),'Padrón importado: '||n||' registros');
 return n;
end; $$;

create or replace function public.sb_save_profiles(p_profiles jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if not public.sb_is_admin() then raise exception 'Acceso no autorizado'; end if;
 if (select is_open from public.sb_election where id=1) then raise exception 'Cierra la elección antes de modificar listas'; end if;
 if jsonb_typeof(p_profiles)<>'object' or not (p_profiles ? 'A') or not(p_profiles ? 'B') or length(p_profiles::text)>700000 then
  raise exception 'Datos de candidaturas inválidos'; end if;
 update public.sb_election set profiles=p_profiles where id=1;
 insert into public.sb_admin_audit(actor,operation) values(auth.uid(),'Candidaturas editadas');
end; $$;

-- Solo un admin autenticado; el navegador exige reautenticar contraseña previamente.
create or replace function public.sb_reset_votes(p_phrase text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if not public.sb_is_admin() then raise exception 'Acceso no autorizado'; end if;
 if p_phrase <> 'REINICIAR VOTOS' then raise exception 'Frase de confirmación incorrecta'; end if;
 if (select is_open from public.sb_election where id=1) then raise exception 'Cierra la elección antes de reiniciar'; end if;
 delete from public.sb_ballots;
 update public.sb_voters set has_voted=false;
 delete from public.sb_attempts;
 insert into public.sb_admin_audit(actor,operation) values(auth.uid(),'Votos reiniciados');
end; $$;

-- Bloquear funciones y tablas; exponer únicamente RPC indicadas.
revoke execute on function public.sb_is_admin() from public, anon, authenticated;
revoke execute on function public.sb_public_config() from public, anon, authenticated;
revoke execute on function public.sb_verify(text,text) from public, anon, authenticated;
revoke execute on function public.sb_cast_vote(text,text,text) from public, anon, authenticated;
revoke execute on function public.sb_admin_snapshot() from public, anon, authenticated;
revoke execute on function public.sb_set_open(boolean) from public, anon, authenticated;
revoke execute on function public.sb_import_roster(jsonb,boolean) from public, anon, authenticated;
revoke execute on function public.sb_save_profiles(jsonb) from public, anon, authenticated;
revoke execute on function public.sb_reset_votes(text) from public, anon, authenticated;
grant execute on function public.sb_public_config() to anon,authenticated;
grant execute on function public.sb_verify(text,text) to anon;
grant execute on function public.sb_cast_vote(text,text,text) to anon;
grant execute on function public.sb_admin_snapshot() to authenticated;
grant execute on function public.sb_set_open(boolean) to authenticated;
grant execute on function public.sb_import_roster(jsonb,boolean) to authenticated;
grant execute on function public.sb_save_profiles(jsonb) to authenticated;
grant execute on function public.sb_reset_votes(text) to authenticated;

-- PASO FINAL MANUAL: tras crear usuario administrador en Supabase Auth > Users,
-- ejecutar esta instrucción cambiando el correo por el que realmente creaste:
-- insert into public.sb_admins(user_id)
-- select id from auth.users where email='admin@tuinstitucion.edu.ec'
-- on conflict do nothing;



-- MÓDULO DE OBSERVACIÓN: instalar DESPUÉS de database.sql inicial.
-- El observador es un usuario autenticado, autorizado explícitamente por el dueño.
create table if not exists public.sb_observers (
 user_id uuid primary key references auth.users(id) on delete cascade,
 granted_at timestamptz not null default now()
);
alter table public.sb_observers enable row level security;
revoke all on public.sb_observers from anon, authenticated;

-- Acceso de lectura restringido a observadores y administradores.
-- Devuelve agregados A/B/BLANCO/NULO independientemente del estado para observación.
-- No devuelve relaciones entre voto y elector, ni los PIN/hash.
create or replace function public.sb_observer_snapshot()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare cfg public.sb_election%rowtype; r jsonb; tally jsonb; turn jsonb;
begin
 if auth.uid() is null or not (
   exists(select 1 from public.sb_observers where user_id=auth.uid())
   or exists(select 1 from public.sb_admins where user_id=auth.uid())
 ) then raise exception 'Acceso no autorizado para observación'; end if;
 select * into cfg from public.sb_election where id=1;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name,'course',course,'voted',has_voted)
   order by course,full_name),'[]'::jsonb) into r from public.sb_voters;
 select jsonb_build_object('total',(select count(*) from public.sb_voters),
   'voted',(select count(*) from public.sb_voters where has_voted)) into turn;
 select jsonb_build_object(
 'A',(select count(*) from public.sb_ballots where choice='A'),
 'B',(select count(*) from public.sb_ballots where choice='B'),
 'BLANCO',(select count(*) from public.sb_ballots where choice='BLANCO'),
 'NULO',(select count(*) from public.sb_ballots where choice='NULO')) into tally;
 return jsonb_build_object('title',cfg.title,'open',cfg.is_open,'closed_at',cfg.closed_at,
  'roster',r,'turnout',turn,'results',tally);
end; $$;
revoke execute on function public.sb_observer_snapshot() from public, anon, authenticated;
grant execute on function public.sb_observer_snapshot() to authenticated;

-- IMPORTANTE: El docente NO se añade a sb_admins, solo a sb_observers.
-- Para autorizar tras crear el usuario en Authentication > Users:
-- insert into public.sb_observers(user_id)
-- select id from auth.users where email='docente@institucion.edu.ec'
-- on conflict do nothing;
-- Para revocar: delete from public.sb_observers where user_id=...;
