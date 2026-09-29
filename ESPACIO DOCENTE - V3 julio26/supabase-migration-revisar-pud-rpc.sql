-- =========================================================
-- Migración: revisar PUD vía función SECURITY DEFINER
-- (cierra la advertencia dejada en supabase-migration-presentar.sql:
-- RLS no restringe QUÉ columnas se actualizan dentro de una fila permitida.
-- Hoy pud_history_update_review_coordinador, de
-- supabase-migration-endurecer-revision-coordinador.sql, deja que cualquier
-- coordinador logueado haga UPDATE de CUALQUIER columna de una fila
-- 'presented' -- incluido el contenido del PUD, no solo el veredicto -- con
-- solo abrir la consola del navegador. Esta migración reemplaza el UPDATE
-- directo desde el cliente por una función que solo puede tocar
-- review_status/review_comment/reviewed_at.)
-- Correr a mano en Supabase SQL Editor. Idempotente.
--
-- OJO: asume que pud_history.id es bigint (el default de Supabase para
-- tablas nuevas, "id bigint generated always as identity"). Si en tu
-- proyecto pud_history.id es uuid, cambiá el tipo del parámetro p_id acá
-- abajo antes de correr esto.
-- =========================================================

CREATE OR REPLACE FUNCTION public.revisar_pud_presentado(
  p_id bigint,
  p_review_status text,
  p_review_comment text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text := auth.jwt() ->> 'email';
BEGIN
  IF p_review_status NOT IN ('approved', 'changes_requested') THEN
    RAISE EXCEPTION 'review_status inválido: %', p_review_status;
  END IF;

  IF p_review_status = 'changes_requested' AND coalesce(trim(p_review_comment), '') = '' THEN
    RAISE EXCEPTION 'Hay que indicar un comentario al solicitar cambios';
  END IF;

  IF v_email IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.coordinadores c WHERE c.email = v_email
  ) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  UPDATE public.pud_history
  SET review_status = p_review_status,
      review_comment = CASE WHEN p_review_status = 'approved' THEN NULL ELSE trim(p_review_comment) END,
      reviewed_at = now()
  WHERE id = p_id
    AND status = 'presented';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PUD no encontrado o no está presentado';
  END IF;
END;
$$;

-- Solo autenticados pueden invocarla; PUBLIC (incluye anon) queda afuera.
REVOKE ALL ON FUNCTION public.revisar_pud_presentado(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revisar_pud_presentado(bigint, text, text) TO authenticated;

-- La función corre como su dueño (SECURITY DEFINER) y ya valida coordinador
-- + status='presented' + qué columnas toca por dentro, así que el UPDATE
-- directo desde el cliente deja de hacer falta. Se saca la policy para que
-- no quede una vía paralela sin la restricción de columnas.
DROP POLICY IF EXISTS pud_history_update_review_coordinador ON public.pud_history;
DROP POLICY IF EXISTS pud_history_update_review_public ON public.pud_history;

-- Nota (queda igual que en la migración anterior, no se resuelve acá): esta
-- función tampoco filtra por el grado/materia que el coordinador tiene
-- permitido en coordinador_permiso_grados/materias -- cualquier coordinador
-- logueado puede aprobar/pedir cambios en filas fuera de su alcance. Si eso
-- importa, agregar ese chequeo (EXISTS contra esas dos tablas, igual que ya
-- hace window.permisosCoordinador en JS) adentro de esta misma función.
