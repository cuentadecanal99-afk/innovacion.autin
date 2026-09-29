-- =========================================================
-- Migración: Nivel Inicial (Sala de 3, 4 y 5) como "año" del PUD.
-- Correr a mano en Supabase SQL Editor. Idempotente.
--
-- La tabla grados es la lista de valores válidos para
-- coordinador_permiso_grados (FK): sin estas filas no se le puede
-- asignar a un coordinador el permiso sobre una sala. Los nombres
-- tienen que coincidir exactamente con GRUPOS_GRADOS en index.html.
-- =========================================================
insert into public.grados (nombre) values
  ('Sala de 3 años'),
  ('Sala de 4 años'),
  ('Sala de 5 años')
on conflict do nothing;
