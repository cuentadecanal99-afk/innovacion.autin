-- =========================================================
-- Migración: Hilos Conductores fijos por área
-- Correr a mano en Supabase SQL Editor. Idempotente.
--
-- Contexto: hasta ahora la IA inventaba 4 "throughlines" (hilos
-- conductores) nuevos en cada PUD generado. En EpC los hilos
-- conductores son fijos por MATERIA (no cambian por unidad, grado
-- ni año) — lo único que varía es cómo se aplican/redactan según
-- la edad y el contenido de cada unidad puntual.
--
-- Esta tabla guarda esos 4 hilos fijos por área (uno por cada
-- dimensión KNOWLEDGE/METHOD/PURPOSE/COMMUNICATION, el mismo orden
-- fijo que ya usa prepararPromptParaIA() en index.html para los 4
-- 'understanding_goals'). El prompt los usa como referencia y le
-- pide a la IA que los adapte a la unidad, no que invente otros.
--
-- Los datos insertados abajo son DEMO / placeholder para las áreas
-- que ya existen hoy en 'areas' — reemplazalos a mano desde el
-- Table Editor de Supabase por los hilos reales de cada materia.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.hilos_conductores (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  area_id bigint NOT NULL REFERENCES public.areas(id) ON DELETE CASCADE,
  dimension text NOT NULL CHECK (dimension IN ('KNOWLEDGE', 'METHOD', 'PURPOSE', 'COMMUNICATION')),
  hilo text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (area_id, dimension)
);

ALTER TABLE public.hilos_conductores ENABLE ROW LEVEL SECURITY;

-- Solo lectura desde la app (docentes, con o sin sesión). La edición
-- de los hilos se hace a mano desde el dashboard de Supabase (que usa
-- el rol de servicio y no pasa por RLS), no hay flujo de escritura
-- desde el front todavía.
DROP POLICY IF EXISTS hilos_conductores_select_all ON public.hilos_conductores;
CREATE POLICY hilos_conductores_select_all ON public.hilos_conductores
  FOR SELECT USING (true);

-- Datos demo: 4 hilos (uno por dimensión) para cada área ya cargada
-- en 'areas'. Si el área todavía no existe no se inserta nada para
-- ella (ON CONFLICT protege contra reinserciones si se corre de nuevo).
INSERT INTO public.hilos_conductores (area_id, dimension, hilo)
SELECT a.id, v.dimension, v.hilo
FROM public.areas a
JOIN (VALUES
  -- Sociales
  ('Sociales', 'KNOWLEDGE',     '¿Cómo se organizan y transforman las sociedades a lo largo del tiempo y el espacio?'),
  ('Sociales', 'METHOD',        '¿Cómo se investigan, comparan y validan fuentes para comprender procesos sociales?'),
  ('Sociales', 'PURPOSE',       '¿Por qué es importante comprender la sociedad para participar como ciudadanos activos?'),
  ('Sociales', 'COMMUNICATION', '¿Cómo comunicamos de manera clara y fundamentada nuestras interpretaciones sobre la realidad social?'),

  -- Naturales
  ('Naturales', 'KNOWLEDGE',     '¿Cómo funcionan los sistemas naturales y qué relaciones existen entre sus componentes?'),
  ('Naturales', 'METHOD',        '¿Cómo se diseñan y llevan a cabo investigaciones científicas para explicar fenómenos naturales?'),
  ('Naturales', 'PURPOSE',       '¿Por qué es importante el pensamiento científico para cuidar el ambiente y tomar decisiones informadas?'),
  ('Naturales', 'COMMUNICATION', '¿Cómo comunicamos hallazgos científicos de forma clara, precisa y basada en evidencia?'),

  -- Lengua
  ('Lengua', 'KNOWLEDGE',     '¿Cómo se construyen los significados a través del lenguaje oral y escrito?'),
  ('Lengua', 'METHOD',        '¿Qué estrategias de lectura y escritura permiten comprender y producir distintos tipos de textos?'),
  ('Lengua', 'PURPOSE',       '¿Por qué el lenguaje es una herramienta central para pensar, aprender y participar en la sociedad?'),
  ('Lengua', 'COMMUNICATION', '¿Cómo adaptamos nuestra comunicación según la intención, el destinatario y el contexto?'),

  -- Matemática
  ('Matemática', 'KNOWLEDGE',     '¿Qué relaciones y estructuras matemáticas subyacen a los problemas cotidianos y disciplinares?'),
  ('Matemática', 'METHOD',        '¿Qué estrategias y procedimientos permiten resolver problemas matemáticos de manera eficaz?'),
  ('Matemática', 'PURPOSE',       '¿Por qué el pensamiento matemático es una herramienta para interpretar y transformar el mundo?'),
  ('Matemática', 'COMMUNICATION', '¿Cómo comunicamos razonamientos y resultados matemáticos con precisión y claridad?'),

  -- Social Studies
  ('Social Studies', 'KNOWLEDGE',     'How are societies organized and transformed across time and place?'),
  ('Social Studies', 'METHOD',        'How do we investigate, compare, and validate sources to understand social processes?'),
  ('Social Studies', 'PURPOSE',       'Why does understanding societies matter for active, informed citizenship?'),
  ('Social Studies', 'COMMUNICATION', 'How do we communicate well-reasoned interpretations of social reality clearly?'),

  -- Speaking WS
  ('Speaking WS', 'KNOWLEDGE',     'What makes spoken communication clear, coherent, and purposeful?'),
  ('Speaking WS', 'METHOD',        'What strategies help structure and deliver an effective spoken message?'),
  ('Speaking WS', 'PURPOSE',       'Why does confident, articulate speaking matter for expressing ideas and connecting with others?'),
  ('Speaking WS', 'COMMUNICATION', 'How do we adapt tone, register, and delivery to different audiences and purposes?'),

  -- Language Arts
  ('Language Arts', 'KNOWLEDGE',     'How is meaning built and interpreted through spoken and written language?'),
  ('Language Arts', 'METHOD',        'What reading and writing strategies support comprehension and effective composition?'),
  ('Language Arts', 'PURPOSE',       'Why is language a central tool for thinking, learning, and participating in society?'),
  ('Language Arts', 'COMMUNICATION', 'How do we adjust our communication to purpose, audience, and context?'),

  -- Citizenship
  ('Citizenship', 'KNOWLEDGE',     'What rights, responsibilities, and structures define life in a community?'),
  ('Citizenship', 'METHOD',        'How do we analyze real situations to make informed, ethical decisions as citizens?'),
  ('Citizenship', 'PURPOSE',       'Why does active, responsible participation matter for building fair communities?'),
  ('Citizenship', 'COMMUNICATION', 'How do we express and defend our point of view respectfully in a diverse community?'),

  -- Geografia
  ('Geografia', 'KNOWLEDGE',     '¿Cómo interactúan los elementos naturales y humanos en la organización del espacio geográfico?'),
  ('Geografia', 'METHOD',        '¿Qué herramientas y fuentes permiten analizar e interpretar el territorio?'),
  ('Geografia', 'PURPOSE',       '¿Por qué comprender el espacio geográfico ayuda a tomar decisiones sobre el ambiente y la sociedad?'),
  ('Geografia', 'COMMUNICATION', '¿Cómo representamos y comunicamos información geográfica de forma clara (mapas, gráficos, textos)?'),

  -- Historia
  ('Historia', 'KNOWLEDGE',     '¿Cómo se explican los procesos históricos a partir de sus causas, actores y consecuencias?'),
  ('Historia', 'METHOD',        '¿Cómo se analizan fuentes históricas para construir explicaciones fundamentadas del pasado?'),
  ('Historia', 'PURPOSE',       '¿Por qué comprender el pasado es clave para interpretar el presente y proyectar el futuro?'),
  ('Historia', 'COMMUNICATION', '¿Cómo comunicamos una interpretación histórica de manera clara y argumentada?'),

  -- Literature
  ('Literature', 'KNOWLEDGE',     'How do literary texts reflect and shape human experience across cultures and time?'),
  ('Literature', 'METHOD',        'What strategies help us analyze and interpret literary texts closely?'),
  ('Literature', 'PURPOSE',       'Why does engaging with literature deepen empathy and understanding of the world?'),
  ('Literature', 'COMMUNICATION', 'How do we express and support literary interpretations clearly and persuasively?'),

  -- Prácticas del lenguaje
  ('Prácticas del lenguaje', 'KNOWLEDGE',     '¿Cómo varían las prácticas de lectura, escritura y oralidad según la situación comunicativa?'),
  ('Prácticas del lenguaje', 'METHOD',        '¿Qué estrategias permiten leer, escribir y hablar de manera cada vez más autónoma?'),
  ('Prácticas del lenguaje', 'PURPOSE',       '¿Por qué participar en distintas prácticas del lenguaje amplía nuestra forma de pensar y vincularnos?'),
  ('Prácticas del lenguaje', 'COMMUNICATION', '¿Cómo ajustamos lo que decimos o escribimos según el propósito y el destinatario?')
) AS v(area_name, dimension, hilo) ON v.area_name = a.name
ON CONFLICT (area_id, dimension) DO NOTHING;
