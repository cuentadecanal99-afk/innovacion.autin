-- =========================================================
-- Migración: botón "Presentar" + Panel de Coordinadores
-- Correr a mano en Supabase SQL Editor. Idempotente.
-- =========================================================

-- 1. Columnas nuevas en pud_history (no rompe filas existentes: status default 'draft')
ALTER TABLE public.pud_history
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'draft',
  ADD COLUMN IF NOT EXISTS presented_at timestamptz,
  ADD COLUMN IF NOT EXISTS presented_version integer,
  ADD COLUMN IF NOT EXISTS docente_nombre text;
-- 'status' queda genérico a propósito (no un enum ni tabla de roles): deja
-- lugar a futuros valores tipo 'approved'/'changes_requested' sin migrar de nuevo.

CREATE INDEX IF NOT EXISTS idx_pud_history_coord_lookup
  ON public.pud_history (subject, year, status, presented_at DESC);

-- 2. Tabla de referencia 'areas' (nueva, chica, compartida por docente y coordinadores)
CREATE TABLE IF NOT EXISTS public.areas (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.areas (name) VALUES
  ('Sociales'), ('Naturales'), ('Lengua'), ('Matemática')
ON CONFLICT (name) DO NOTHING;

ALTER TABLE public.areas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS areas_select_all ON public.areas;
CREATE POLICY areas_select_all ON public.areas
  FOR SELECT USING (true);

DROP POLICY IF EXISTS areas_insert_authenticated ON public.areas;
CREATE POLICY areas_insert_authenticated ON public.areas
  FOR INSERT TO authenticated WITH CHECK (true);

-- 3. Política aditiva en pud_history para el panel de coordinadores (sin login)
-- ADVERTENCIA: esta policy solo protege algo si pud_history YA tiene RLS
-- habilitado con políticas propias del docente. Este script NO ejecuta
-- ALTER TABLE pud_history ENABLE ROW LEVEL SECURITY — si hoy no está
-- habilitado y lo activamos a ciegas sin las policies del docente ya
-- puestas, guardarPUD()/recuperarHistorialReal() dejan de funcionar.
-- Antes de correr esto: confirmar en Supabase Dashboard > Authentication >
-- Policies que pud_history tiene RLS ON con políticas propias del docente.
DROP POLICY IF EXISTS pud_history_select_presented_public ON public.pud_history;
CREATE POLICY pud_history_select_presented_public ON public.pud_history
  FOR SELECT TO anon, authenticated
  USING (status = 'presented');
