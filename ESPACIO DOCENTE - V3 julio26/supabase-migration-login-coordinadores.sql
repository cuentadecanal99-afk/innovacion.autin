-- =========================================================
-- Migración: Login + permisos por coordinador
-- Correr a mano en Supabase SQL Editor. Idempotente.
-- =========================================================

-- 1. Tabla de permisos. Se carga a mano desde el Table Editor de Supabase
-- (con tu sesión de dashboard, que no pasa por las RLS de abajo): por cada
-- coordinador, una fila con su email y los grados/materias que puede ver.
-- years/subjects en NULL = sin restricción (ve todos los grados o todas las
-- materias). Mismo criterio que ya usaba window.permisosCoordinador.
CREATE TABLE IF NOT EXISTS public.coordinador_permisos (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email text NOT NULL UNIQUE,
  years text[],
  subjects text[],
  created_at timestamptz NOT NULL DEFAULT now()
);
-- Ejemplo de fila (correr aparte, una vez por coordinador):
-- insert into public.coordinador_permisos (email, years, subjects) values
--   ('coordinadora.primaria@austin.edu.ar', array['1° Grado Primaria','2° Grado Primaria'], null);

ALTER TABLE public.coordinador_permisos ENABLE ROW LEVEL SECURITY;

-- Cada coordinador logueado solo puede leer SU PROPIA fila (no la lista
-- completa de coordinadores ni los permisos de otros). Sin policies de
-- INSERT/UPDATE/DELETE a propósito: esa carga la hacés vos a mano.
DROP POLICY IF EXISTS coordinador_permisos_select_own ON public.coordinador_permisos;
CREATE POLICY coordinador_permisos_select_own ON public.coordinador_permisos
  FOR SELECT TO authenticated
  USING (email = auth.jwt() ->> 'email');

-- 2. Endurecer la policy de lectura de pud_history del panel de
-- coordinadores. Hasta ahora era pública (anon incluido) porque no había
-- login; con login ya andando, dejarla abierta a anon anularía el sentido de
-- los permisos por coordinador (cualquiera con la anon key seguiría leyendo
-- todo sin loguearse). Se reemplaza por "solo autenticado" — el docente no
-- se ve afectado, su propio historial ya se filtra por user_id con otra policy.
DROP POLICY IF EXISTS pud_history_select_presented_public ON public.pud_history;
CREATE POLICY pud_history_select_presented_public ON public.pud_history
  FOR SELECT TO authenticated
  USING (status = 'presented');
