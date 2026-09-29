-- =========================================================
-- Migración v2: permisos de coordinador con selector real
-- (reemplaza el enfoque de supabase-migration-login-coordinadores.sql de
-- guardar years/subjects como texto libre en una sola fila).
-- Correr a mano en Supabase SQL Editor. Idempotente.
-- =========================================================

-- 0. Si ya habías corrido la migración anterior y NO cargaste todavía
-- ningún coordinador real en coordinador_permisos, borrala para no dejar
-- dos sistemas de permisos en paralelo. Si ya cargaste datos ahí, comentá
-- esta línea y migralos a mano a las tablas nuevas antes de seguir.
DROP TABLE IF EXISTS public.coordinador_permisos;

-- 1. Tabla de referencia de grados (misma lista que usa toda la app: ver
-- GRADOS_PRIMARIA en index.html y ORDEN_GRADOS en coordinadores/index.html).
-- Sirve como "lista válida" para que el selector de Supabase no deje
-- escribir cualquier cosa.
CREATE TABLE IF NOT EXISTS public.grados (
  nombre text PRIMARY KEY
);

INSERT INTO public.grados (nombre) VALUES
  ('1° Grado Primaria'), ('2° Grado Primaria'), ('3° Grado Primaria'),
  ('4° Grado Primaria'), ('5° Grado Primaria'), ('6° Grado Primaria')
ON CONFLICT (nombre) DO NOTHING;
-- Las materias reusan la tabla 'areas' que ya existe (mismo listado que usa
-- el desplegable "Materia/Área" del docente) — no hace falta una tabla nueva.

-- 2. Registro de coordinadores habilitados. Tener una fila acá es lo que
-- distingue "sin restricciones, ve todo" de "no tiene ninguna fila de
-- permisos todavía porque no es coordinador" — sin esto no se podría
-- diferenciar un coordinador sin restricciones de una cuenta sin dar de alta.
CREATE TABLE IF NOT EXISTS public.coordinadores (
  email text PRIMARY KEY,
  nombre text,
  created_at timestamptz NOT NULL DEFAULT now()
);
-- Ejemplo (correr aparte, una vez por coordinador):
-- insert into public.coordinadores (email, nombre) values
--   ('coordinadora.primaria@austin.edu.ar', 'Nombre Apellido');

-- 3. Restricciones por grado y por materia: una fila por cada grado/materia
-- al que un coordinador tiene acceso. Sin ninguna fila para un coordinador
-- en una de estas dos tablas = sin restricción en ese eje (ve todos los
-- grados o todas las materias). 'grado'/'materia' son foreign key, así que
-- en el Table Editor de Supabase se cargan con un selector, no a mano.
CREATE TABLE IF NOT EXISTS public.coordinador_permiso_grados (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email text NOT NULL REFERENCES public.coordinadores(email) ON DELETE CASCADE,
  grado text NOT NULL REFERENCES public.grados(nombre),
  UNIQUE (email, grado)
);

CREATE TABLE IF NOT EXISTS public.coordinador_permiso_materias (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email text NOT NULL REFERENCES public.coordinadores(email) ON DELETE CASCADE,
  materia text NOT NULL REFERENCES public.areas(name),
  UNIQUE (email, materia)
);
-- Ejemplo: darle a coordinadora.primaria@austin.edu.ar acceso solo a 3° y 4°
-- grado (todas las materias, porque no se le carga ninguna fila de materias):
-- insert into public.coordinador_permiso_grados (email, grado) values
--   ('coordinadora.primaria@austin.edu.ar', '3° Grado Primaria'),
--   ('coordinadora.primaria@austin.edu.ar', '4° Grado Primaria');

-- 4. RLS: cada coordinador logueado solo puede leer SUS PROPIAS filas.
-- Sin policies de INSERT/UPDATE/DELETE a propósito: esa carga la hacés vos
-- a mano desde el Table Editor (con tu sesión de dashboard).
ALTER TABLE public.coordinadores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coordinadores_select_own ON public.coordinadores;
CREATE POLICY coordinadores_select_own ON public.coordinadores
  FOR SELECT TO authenticated
  USING (email = auth.jwt() ->> 'email');

ALTER TABLE public.coordinador_permiso_grados ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coordinador_permiso_grados_select_own ON public.coordinador_permiso_grados;
CREATE POLICY coordinador_permiso_grados_select_own ON public.coordinador_permiso_grados
  FOR SELECT TO authenticated
  USING (email = auth.jwt() ->> 'email');

ALTER TABLE public.coordinador_permiso_materias ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coordinador_permiso_materias_select_own ON public.coordinador_permiso_materias;
CREATE POLICY coordinador_permiso_materias_select_own ON public.coordinador_permiso_materias
  FOR SELECT TO authenticated
  USING (email = auth.jwt() ->> 'email');

-- 'grados' y 'areas' son listas de referencia compartidas (no datos privados
-- de un coordinador puntual): lectura abierta a cualquier autenticado, igual
-- que ya tiene 'areas' desde la migración anterior.
ALTER TABLE public.grados ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS grados_select_all ON public.grados;
CREATE POLICY grados_select_all ON public.grados
  FOR SELECT USING (true);
