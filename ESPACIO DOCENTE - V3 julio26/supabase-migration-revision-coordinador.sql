-- =========================================================
-- Migración: Aprobar / Solicitar cambios (panel de Coordinadores)
-- Correr a mano en Supabase SQL Editor. Idempotente.
-- =========================================================

-- 1. Columnas nuevas en pud_history para el veredicto del coordinador sobre
-- una versión presentada puntual. Se guardan aparte de 'status' (que sigue
-- siendo solo draft/presented) para no tocar ninguna de las queries que ya
-- filtran por status='presented' en index.html y coordinadores/index.html.
ALTER TABLE public.pud_history
  ADD COLUMN IF NOT EXISTS review_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS review_comment text,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;
-- Valores esperados de review_status: 'pending' | 'approved' | 'changes_requested'.
-- Sin enum a propósito, mismo criterio que 'status'.

CREATE INDEX IF NOT EXISTS idx_pud_history_review_status
  ON public.pud_history (review_status);

-- 2. Policy de UPDATE para que el panel de coordinadores pueda escribir el
-- veredicto. Hoy no hay login de coordinador, así que queda abierta a
-- anon/authenticated igual que la policy de SELECT existente.
-- ADVERTENCIA (mismo alcance que la policy de SELECT de la migración
-- anterior): esto solo importa si pud_history ya tiene RLS habilitado. Si no
-- lo tiene, esta policy no hace nada (ni falta, ni protege). Y aunque exista,
-- Postgres RLS no restringe QUÉ columnas se actualizan dentro de una fila
-- permitida: cualquiera con la anon key podría en teoría pisar otros campos
-- de una fila presentada. Es el mismo nivel de confianza "sin login todavía"
-- que ya tiene el resto del panel de coordinadores — para producción real,
-- este es el primer lugar donde conviene agregar autenticación de coordinador.
DROP POLICY IF EXISTS pud_history_update_review_public ON public.pud_history;
CREATE POLICY pud_history_update_review_public ON public.pud_history
  FOR UPDATE TO anon, authenticated
  USING (status = 'presented')
  WITH CHECK (status = 'presented');
