-- =========================================================
-- Migración: grados de secundaria + evitar materias duplicadas por sintaxis
-- Correr a mano en Supabase SQL Editor. Idempotente.
-- =========================================================

-- 1. Suma los 6 años de secundaria a la lista de grados válidos para el
-- selector de permisos del coordinador (ver supabase-migration-permisos-
-- coordinador-v2.sql). El desplegable "Año" del docente (index.html) y el
-- orden del gráfico de barras (coordinadores/index.html) ya se actualizaron
-- en el código para incluirlos.
-- CREATE TABLE defensivo por si esta migración se corre antes que
-- supabase-migration-permisos-coordinador-v2.sql (no pisa la tabla si ya
-- existe con datos).
CREATE TABLE IF NOT EXISTS public.grados (
  nombre text PRIMARY KEY
);

INSERT INTO public.grados (nombre) VALUES
  ('1° Año Secundaria'), ('2° Año Secundaria'), ('3° Año Secundaria'),
  ('4° Año Secundaria'), ('5° Año Secundaria'), ('6° Año Secundaria')
ON CONFLICT (nombre) DO NOTHING;

-- 2. Evitar que "Matemática" y "matematica" (o "MATEMATICA") queden como dos
-- materias distintas en la tabla 'areas'. El UNIQUE actual en 'name' solo
-- bloquea un duplicado carácter por carácter idéntico; esto agrega un índice
-- único sobre el nombre normalizado (minúsculas + sin tildes), así cualquier
-- variante de escritura choca contra la misma fila.
--
-- unaccent() no es IMMUTABLE por defecto en Postgres (no se puede usar
-- directo en un índice); se fija el diccionario a mano para que sí lo sea
-- — es el workaround estándar documentado por PostgreSQL para este caso.
--
-- Se fuerza el esquema a 'public' en vez de dejar que Supabase elija (suele
-- instalarlo en 'extensions'), porque Postgres evalúa las expresiones de un
-- índice con un search_path acotado: una referencia sin esquema como
-- 'unaccent'::regdictionary no se resuelve ahí aunque funcione en una
-- consulta suelta. Por eso además se cualifica 'public.unaccent' a mano.
DROP FUNCTION IF EXISTS public.areas_nombre_normalizado(text);
DROP EXTENSION IF EXISTS unaccent;
CREATE EXTENSION unaccent SCHEMA public;

CREATE OR REPLACE FUNCTION public.areas_nombre_normalizado(texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(public.unaccent('public.unaccent'::regdictionary, texto));
$$;

-- ADVERTENCIA: si ya existen en 'areas' dos filas que normalizan igual (ej.
-- alguien ya cargó "Matemática" Y "matematica" antes de esta migración), este
-- CREATE INDEX va a fallar con "could not create unique index" — hay que
-- borrar/fusionar el duplicado a mano primero y volver a correr esta parte.
CREATE UNIQUE INDEX IF NOT EXISTS idx_areas_nombre_normalizado
  ON public.areas (public.areas_nombre_normalizado(name));
