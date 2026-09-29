-- =========================================================
-- Migración: cerrar el acceso anónimo a aprobar/pedir cambios
-- (endurece la policy que dejó abierta
-- supabase-migration-revision-coordinador.sql antes de que existiera login).
-- Correr a mano en Supabase SQL Editor. Idempotente.
-- =========================================================

-- Hasta ahora esta policy permitía a CUALQUIERA con la anon key (la que
-- viaja en el JS del sitio, visible para cualquier visitante) aprobar o
-- pedir cambios sobre cualquier PUD presentado, sin loguearse. Se reemplaza
-- por: solo usuarios logueados que además están de alta en 'coordinadores'
-- (mismo criterio de alta que ya usa el resto del panel, ver
-- supabase-migration-permisos-coordinador-v2.sql).
DROP POLICY IF EXISTS pud_history_update_review_public ON public.pud_history;
DROP POLICY IF EXISTS pud_history_update_review_coordinador ON public.pud_history;
CREATE POLICY pud_history_update_review_coordinador ON public.pud_history
  FOR UPDATE TO authenticated
  USING (
    status = 'presented'
    AND EXISTS (
      SELECT 1 FROM public.coordinadores c
      WHERE c.email = auth.jwt() ->> 'email'
    )
  )
  WITH CHECK (
    status = 'presented'
    AND EXISTS (
      SELECT 1 FROM public.coordinadores c
      WHERE c.email = auth.jwt() ->> 'email'
    )
  );

-- Nota: esta policy no restringe la aprobación al grado/materia que el
-- coordinador tiene permitido en coordinador_permiso_grados/materias — eso
-- hoy solo se filtra en el JS del panel (window.permisosCoordinador), no a
-- nivel de base. Cualquier coordinador logueado puede, en teoría, aprobar
-- filas fuera de su alcance abriendo la consola del navegador. Si eso
-- importa, es un endurecimiento aparte (agregar esa restricción también a
-- esta policy).
