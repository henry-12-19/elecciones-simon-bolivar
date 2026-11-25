-- ACTUALIZACIÓN A VOTACIÓN LIBRE SIN PADRÓN
-- Ejecutar una sola vez con la elección CERRADA, después de guardar respaldo.
-- No elimina la tabla sb_voters ni las papeletas existentes.
-- ¡IMPORTANTE! Sin identificación no se puede garantizar un voto por persona.
BEGIN;

-- Bloquear operaciones de votación anteriores, evitando rutas alternativas.
DO $$
DECLARE f record;
BEGIN
 FOR f IN SELECT p.oid::regprocedure AS sig
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN ('sb_verify','sb_cast_vote','sb_import_roster') LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',f.sig);
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.sb_cast_open_vote(p_choice text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE opened boolean;
BEGIN
 IF p_choice IS NULL OR p_choice NOT IN ('A','B','BLANCO','NULO') THEN
  RETURN jsonb_build_object('ok',false,'message','Selección no válida');
 END IF;
 -- Se sincroniza con el cierre: transacciones de cierre esperan por los votos en curso.
 SELECT is_open INTO opened FROM public.sb_election WHERE id=1 FOR SHARE;
 IF NOT COALESCE(opened,false) THEN
   RETURN jsonb_build_object('ok',false,'message','La elección está cerrada');
 END IF;
 INSERT INTO public.sb_ballots(choice) VALUES(p_choice);
 RETURN jsonb_build_object('ok',true,'message','Voto registrado');
END; $$;
REVOKE ALL ON FUNCTION public.sb_cast_open_vote(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sb_cast_open_vote(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.sb_set_open(p_open boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.sb_is_admin() THEN RAISE EXCEPTION 'Acceso no autorizado'; END IF;
 UPDATE public.sb_election SET is_open=p_open,
 opened_at=CASE WHEN p_open THEN now() ELSE opened_at END,
 closed_at=CASE WHEN p_open THEN NULL ELSE now() END WHERE id=1;
 INSERT INTO public.sb_admin_audit(actor,operation)
 VALUES(auth.uid(), CASE WHEN p_open THEN 'Elección abierta (voto libre)' ELSE 'Elección cerrada' END);
END; $$;

CREATE OR REPLACE FUNCTION public.sb_admin_snapshot()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE cfg public.sb_election%rowtype; results jsonb;
BEGIN
 IF NOT public.sb_is_admin() THEN RAISE EXCEPTION 'Acceso no autorizado'; END IF;
 SELECT * INTO cfg FROM public.sb_election WHERE id=1;
 IF cfg.is_open THEN results:=NULL;
 ELSE SELECT jsonb_build_object(
 'A',(select count(*) from public.sb_ballots where choice='A'),
 'B',(select count(*) from public.sb_ballots where choice='B'),
 'BLANCO',(select count(*) from public.sb_ballots where choice='BLANCO'),
 'NULO',(select count(*) from public.sb_ballots where choice='NULO')) INTO results;
 END IF;
 RETURN jsonb_build_object('title',cfg.title,'open',cfg.is_open,
   'profiles',cfg.profiles,'roster','[]'::jsonb,
   'turnout',jsonb_build_object('voted',(SELECT count(*) FROM public.sb_ballots)),
   'results',results,
   'audit',(SELECT coalesce(jsonb_agg(jsonb_build_object('action',operation,'date',created_at) ORDER BY created_at DESC),'[]'::jsonb)
     FROM (SELECT operation,created_at FROM public.sb_admin_audit ORDER BY audit_id DESC LIMIT 30) a));
END; $$;

CREATE OR REPLACE FUNCTION public.sb_observer_snapshot()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE cfg public.sb_election%rowtype; results jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT (
  EXISTS(SELECT 1 FROM public.sb_observers WHERE user_id=auth.uid())
  OR EXISTS(SELECT 1 FROM public.sb_admins WHERE user_id=auth.uid())
 ) THEN RAISE EXCEPTION 'Acceso no autorizado'; END IF;
 SELECT * INTO cfg FROM public.sb_election WHERE id=1;
 SELECT jsonb_build_object(
 'A',(select count(*) from public.sb_ballots where choice='A'),
 'B',(select count(*) from public.sb_ballots where choice='B'),
 'BLANCO',(select count(*) from public.sb_ballots where choice='BLANCO'),
 'NULO',(select count(*) from public.sb_ballots where choice='NULO')) INTO results;
 RETURN jsonb_build_object('title',cfg.title,'open',cfg.is_open,
  'closed_at',cfg.closed_at,'roster','[]'::jsonb,
  'turnout',jsonb_build_object('voted',(SELECT count(*) FROM public.sb_ballots)),
  'results',results);
END; $$;

-- Reinicio del escrutinio; WHERE explicito para cumplir política DELETE del proyecto.
CREATE OR REPLACE FUNCTION public.sb_reset_votes(p_phrase text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.sb_is_admin() THEN RAISE EXCEPTION 'Acceso no autorizado'; END IF;
 IF p_phrase <> 'REINICIAR VOTOS' THEN RAISE EXCEPTION 'Confirmación incorrecta'; END IF;
 IF (SELECT is_open FROM public.sb_election WHERE id=1) THEN
  RAISE EXCEPTION 'Cierra la elección antes de reiniciar'; END IF;
 DELETE FROM public.sb_ballots WHERE ballot_id IS NOT NULL;
 -- Para compatibilidad con pruebas antiguas; no interviene en la votación libre.
 UPDATE public.sb_voters SET has_voted=false WHERE has_voted=true;
 INSERT INTO public.sb_admin_audit(actor,operation) VALUES(auth.uid(),'Votos reiniciados (voto libre)');
END; $$;

-- Las funciones privadas deben ejecutarse solo por usuarios autenticados y autorizados.
REVOKE ALL ON FUNCTION public.sb_admin_snapshot() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sb_observer_snapshot() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sb_set_open(boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sb_reset_votes(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sb_admin_snapshot() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sb_observer_snapshot() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sb_set_open(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sb_reset_votes(text) TO authenticated;
COMMIT;
