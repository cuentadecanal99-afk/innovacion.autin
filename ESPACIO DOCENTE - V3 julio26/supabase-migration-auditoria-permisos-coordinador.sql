-- =========================================================
-- Migración: auditoría en coordinador_permiso_grados/materias
-- (coordinadores ya tiene created_at desde
-- supabase-migration-permisos-coordinador-v2.sql; estas dos tablas
-- quedaron afuera. Sin esto, en unos meses "¿por qué esta persona ve tal
-- grado?" no tiene respuesta -- no hay ni cuándo se cargó ni quién lo hizo.)
-- Correr a mano en Supabase SQL Editor. Idempotente.
-- =========================================================

ALTER TABLE public.coordinador_permiso_grados
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS created_by text;

ALTER TABLE public.coordinador_permiso_materias
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS created_by text;

COMMENT ON COLUMN public.coordinador_permiso_grados.created_by IS
  'Quién cargó el permiso. Se completa a mano al insertar la fila en el Table Editor (nombre o email de quien administra Supabase) -- estas filas se cargan directo con la sesión de dashboard, no hay auth.uid() de la app para capturarlo solo.';
COMMENT ON COLUMN public.coordinador_permiso_materias.created_by IS
  'Quién cargó el permiso. Mismo criterio que coordinador_permiso_grados.created_by.';

-- Nota: coordinadores.created_at existe pero tampoco tiene "quién dio de
-- alta" a ese coordinador. Si eso también importa para la auditoría, es el
-- mismo patrón: ALTER TABLE public.coordinadores ADD COLUMN IF NOT EXISTS
-- created_by text; -- no lo agrego acá porque no fue parte de lo pedido,
-- pero queda a un paso si hace falta.
