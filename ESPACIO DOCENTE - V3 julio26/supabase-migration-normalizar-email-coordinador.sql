-- =========================================================
-- Migración: normalizar emails de coordinador (minúsculas + sin espacios)
-- (el match entre auth.jwt() ->> 'email', coordinadores.email y las tablas
-- de permisos era texto exacto: una mayúscula de más al cargar el alta a
-- mano en el Table Editor, o un espacio pegado sin querer, rompía todo en
-- silencio -- "Tu cuenta todavía no tiene permisos asignados" -- sin ninguna
-- pista de que la causa es un typo de mayúsculas.)
-- Correr a mano en Supabase SQL Editor. Idempotente.
-- =========================================================

-- 1. Normalizar los datos que ya existen. Si esto falla por conflicto de
-- primary key en 'coordinadores', significa que hay dos filas para el mismo
-- email salvo mayúsculas/espacios: borrá el duplicado a mano y volvé a correr.
UPDATE public.coordinadores
  SET email = lower(trim(email))
  WHERE email <> lower(trim(email));

UPDATE public.coordinador_permiso_grados
  SET email = lower(trim(email))
  WHERE email <> lower(trim(email));

UPDATE public.coordinador_permiso_materias
  SET email = lower(trim(email))
  WHERE email <> lower(trim(email));

-- 2. Trigger para que toda alta/edición futura (a mano desde el Table
-- Editor, que no pasa por RLS ni por el JS del panel) quede normalizada
-- también, sin depender de que quien carga los datos se acuerde de escribir
-- todo en minúsculas.
CREATE OR REPLACE FUNCTION public.normalizar_email_coordinador()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.email := lower(trim(NEW.email));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalizar_email ON public.coordinadores;
CREATE TRIGGER trg_normalizar_email
  BEFORE INSERT OR UPDATE OF email ON public.coordinadores
  FOR EACH ROW EXECUTE FUNCTION public.normalizar_email_coordinador();

DROP TRIGGER IF EXISTS trg_normalizar_email ON public.coordinador_permiso_grados;
CREATE TRIGGER trg_normalizar_email
  BEFORE INSERT OR UPDATE OF email ON public.coordinador_permiso_grados
  FOR EACH ROW EXECUTE FUNCTION public.normalizar_email_coordinador();

DROP TRIGGER IF EXISTS trg_normalizar_email ON public.coordinador_permiso_materias;
CREATE TRIGGER trg_normalizar_email
  BEFORE INSERT OR UPDATE OF email ON public.coordinador_permiso_materias
  FOR EACH ROW EXECUTE FUNCTION public.normalizar_email_coordinador();

-- 3. Las policies y la función de revisión comparan contra
-- auth.jwt() ->> 'email', que refleja el email tal como quedó en
-- auth.users -- no necesariamente en minúsculas (depende de cómo se haya
-- creado la cuenta). Se agrega lower() de los dos lados para no depender de
-- que las dos fuentes coincidan en mayúsculas.
DROP POLICY IF EXISTS coordinadores_select_own ON public.coordinadores;
CREATE POLICY coordinadores_select_own ON public.coordinadores
  FOR SELECT TO authenticated
  USING (email = lower(auth.jwt() ->> 'email'));

DROP POLICY IF EXISTS coordinador_permiso_grados_select_own ON public.coordinador_permiso_grados;
CREATE POLICY coordinador_permiso_grados_select_own ON public.coordinador_permiso_grados
  FOR SELECT TO authenticated
  USING (email = lower(auth.jwt() ->> 'email'));

DROP POLICY IF EXISTS coordinador_permiso_materias_select_own ON public.coordinador_permiso_materias;
CREATE POLICY coordinador_permiso_materias_select_own ON public.coordinador_permiso_materias
  FOR SELECT TO authenticated
  USING (email = lower(auth.jwt() ->> 'email'));

-- 4. Mismo criterio en revisar_pud_presentado (ver
-- supabase-migration-revisar-pud-rpc.sql): comparar en minúsculas contra
-- coordinadores.email.
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
  v_email text := lower(trim(auth.jwt() ->> 'email'));
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

-- Nota: el JS del panel (coordinadores/index.html, cargarPermisosCoordinador)
-- también se corrigió para normalizar el email a minúsculas antes de armar
-- el .eq('email', email) contra estas tablas -- las policies de arriba
-- resuelven el filtrado de RLS, pero el WHERE explícito de esa consulta es
-- comparación exacta y necesita el mismo criterio.
