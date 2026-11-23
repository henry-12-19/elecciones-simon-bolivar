

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
