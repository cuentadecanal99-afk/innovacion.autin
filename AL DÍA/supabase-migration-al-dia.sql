-- ═══════════════════════════════════════════════════════════════
-- AL DÍA · Austin Eco Bilingual School
-- Pasa la maqueta de austin-al-dia.html a datos reales en Supabase:
-- cápsulas de formación continua, confirmaciones por docente,
-- encuestas internas y respuestas.
--
-- Reutiliza las tablas `coordinadores` y `directores` ya creadas
-- para Espacio Docente / Onboarding como fuente de permisos: quien
-- ya coordina PUDs o ya es Dirección, coordina/lee Al Día también.
-- ═══════════════════════════════════════════════════════════════

-- ---------- Cápsulas ----------
create table if not exists public.capsulas (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  resumen text,
  autor text,
  tipo text,
  min_lectura integer not null default 5,
  cuerpo jsonb not null default '[]'::jsonb,
  recursos jsonb not null default '[]'::jsonb,
  chequeo jsonb,
  destinatarios text not null default 'todos'
    check (destinatarios in ('todos','secundaria','primaria','kinder','directivo')),
  publicado_en timestamptz not null default now(),
  plazo_dias integer not null default 21,
  futura boolean not null default false,
  creado_por text,
  created_at timestamptz not null default now()
);

comment on column public.capsulas.plazo_dias is 'Días desde publicado_en para contar una confirmación como "a tiempo" en vez de "tarde".';
comment on column public.capsulas.futura is 'Programada/no publicada todavía: se muestra como aviso, sin contenido ni chequeo habilitado.';

-- ---------- Confirmaciones de cápsula (una por docente y cápsula) ----------
create table if not exists public.capsula_confirmaciones (
  id bigint generated always as identity primary key,
  capsula_id uuid not null references public.capsulas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  respuesta_index integer,
  correcta boolean,
  confirmado_at timestamptz not null default now(),
  unique (capsula_id, user_id)
);

-- ---------- Encuestas ----------
create table if not exists public.encuestas (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  preguntas jsonb not null default '[]'::jsonb,
  destinatarios text not null default 'todos'
    check (destinatarios in ('todos','secundaria','primaria','kinder','directivo')),
  abierta boolean not null default true,
  cierra_en timestamptz,
  creado_por text,
  created_at timestamptz not null default now()
);

-- ---------- Respuestas de encuesta (una por docente y encuesta) ----------
create table if not exists public.encuesta_respuestas (
  id bigint generated always as identity primary key,
  encuesta_id uuid not null references public.encuestas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  respuestas jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (encuesta_id, user_id)
);

-- ═══════════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════════
alter table public.capsulas enable row level security;
alter table public.capsula_confirmaciones enable row level security;
alter table public.encuestas enable row level security;
alter table public.encuesta_respuestas enable row level security;

-- Cápsulas: cualquier cuenta autenticada ve el catálogo (el contenido de las
-- "futuras" lo oculta la propia app); solo coordinadores/directores publican.
create policy capsulas_select_authenticated on public.capsulas
  for select to authenticated using (true);

create policy capsulas_write_coordinador on public.capsulas
  for all to authenticated
  using (
    exists (select 1 from public.coordinadores c where c.email = (auth.jwt() ->> 'email'))
    or exists (select 1 from public.directores d where d.email = (auth.jwt() ->> 'email'))
  )
  with check (
    exists (select 1 from public.coordinadores c where c.email = (auth.jwt() ->> 'email'))
    or exists (select 1 from public.directores d where d.email = (auth.jwt() ->> 'email'))
  );

-- Encuestas: mismo criterio que cápsulas.
create policy encuestas_select_authenticated on public.encuestas
  for select to authenticated using (true);

create policy encuestas_write_coordinador on public.encuestas
  for all to authenticated
  using (
    exists (select 1 from public.coordinadores c where c.email = (auth.jwt() ->> 'email'))
    or exists (select 1 from public.directores d where d.email = (auth.jwt() ->> 'email'))
  )
  with check (
    exists (select 1 from public.coordinadores c where c.email = (auth.jwt() ->> 'email'))
    or exists (select 1 from public.directores d where d.email = (auth.jwt() ->> 'email'))
  );

-- Confirmaciones: cada docente ve y crea la suya; coordinación y dirección
-- ven todas (para el seguimiento y el panel), nadie edita la de otro.
create policy confirmaciones_select_own on public.capsula_confirmaciones
  for select to authenticated using (user_id = auth.uid());

create policy confirmaciones_select_coordinador on public.capsula_confirmaciones
  for select to authenticated using (
    exists (select 1 from public.coordinadores c where c.email = (auth.jwt() ->> 'email'))
    or exists (select 1 from public.directores d where d.email = (auth.jwt() ->> 'email'))
  );

create policy confirmaciones_insert_own on public.capsula_confirmaciones
  for insert to authenticated with check (user_id = auth.uid());

create policy confirmaciones_update_own on public.capsula_confirmaciones
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Respuestas de encuesta: mismo criterio que confirmaciones. Las respuestas
-- abiertas se muestran siempre agregadas/anónimas desde la propia app.
create policy respuestas_select_own on public.encuesta_respuestas
  for select to authenticated using (user_id = auth.uid());

create policy respuestas_select_coordinador on public.encuesta_respuestas
  for select to authenticated using (
    exists (select 1 from public.coordinadores c where c.email = (auth.jwt() ->> 'email'))
    or exists (select 1 from public.directores d where d.email = (auth.jwt() ->> 'email'))
  );

create policy respuestas_insert_own on public.encuesta_respuestas
  for insert to authenticated with check (user_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════
-- RPC: matriz de seguimiento con nombre/email
-- (auth.users no es legible por PostgREST; hace falta SECURITY DEFINER,
-- igual que director_onboarding_overview en Onboarding)
-- ═══════════════════════════════════════════════════════════════
create or replace function public.aldia_seguimiento_capsulas()
returns table(user_id uuid, email text, capsula_id uuid, estado text, confirmado_at timestamptz)
language sql
security definer
set search_path to 'public'
as $$
  with autorizado as (
    select
      exists (select 1 from public.coordinadores c where c.email = (auth.jwt() ->> 'email'))
      or exists (select 1 from public.directores d where d.email = (auth.jwt() ->> 'email'))
      as ok
  ),
  personas as (
    select user_id from public.capsula_confirmaciones
    union
    select user_id from public.encuesta_respuestas
  )
  select
    u.id as user_id,
    u.email,
    k.id as capsula_id,
    case
      when c.confirmado_at is null then 'no'
      when c.confirmado_at <= k.publicado_en + (k.plazo_dias || ' days')::interval then 'si'
      else 'tarde'
    end as estado,
    c.confirmado_at
  from auth.users u
  join personas p on p.user_id = u.id
  cross join public.capsulas k
  left join public.capsula_confirmaciones c on c.capsula_id = k.id and c.user_id = u.id
  where k.futura = false
    and (select ok from autorizado)
  order by u.email, k.publicado_en;
$$;

grant execute on function public.aldia_seguimiento_capsulas() to authenticated;

-- ═══════════════════════════════════════════════════════════════
-- Contenido inicial real (el mismo contenido pedagógico que estaba
-- escrito a mano en la maqueta austin-al-dia.html, ahora persistido).
-- Sin confirmaciones/respuestas: arrancan en cero, se completan con uso real.
-- ═══════════════════════════════════════════════════════════════
insert into public.capsulas (titulo, resumen, autor, tipo, min_lectura, cuerpo, recursos, chequeo, publicado_en, futura)
values
('Metas de comprensión: qué las diferencia de un objetivo',
 'Una meta de comprensión no dice qué van a hacer los alumnos, dice qué van a entender. La distinción cambia el PUD entero.',
 'Coordinación Pedagógica', 'EpC', 6,
 '["El objetivo describe la actividad: <em>los alumnos investigarán los ecosistemas de la región</em>. La meta de comprensión describe lo que queda cuando la actividad terminó: <strong>los alumnos comprenderán que un ecosistema se sostiene por relaciones, no por la suma de sus especies</strong>.","La prueba es simple. Si la frase se puede completar con <em>los alumnos harán…</em>, es una actividad. Si se completa con <em>los alumnos comprenderán que…</em>, es una meta.","Escribirla primero ordena el resto del PUD: los desempeños de comprensión se vuelven las formas de poner esa idea en juego, y la evaluación continua deja de ser una nota al pie."]'::jsonb,
 '[["Instructivo PUD · Austin","PDF · 6 páginas"],["Metas reescritas: antes y después","PDF · 2 páginas"]]'::jsonb,
 '{"p":"¿Cuál de estas cuatro es una meta de comprensión y no un objetivo de actividad?","op":["Los alumnos elaborarán una maqueta del ecosistema del humedal.","Los alumnos comprenderán que las decisiones humanas alteran equilibrios que no se ven a simple vista.","Los alumnos investigarán tres especies autóctonas de la zona.","Los alumnos presentarán su trabajo ante el curso."],"ok":1}'::jsonb,
 now() - interval '6 months', false),

('La escalera de retroalimentación, en cuatro peldaños',
 'Clarificar, valorar, expresar inquietudes, sugerir. En ese orden, y sin saltearse el segundo.',
 'Coordinación Pedagógica', 'Retroalimentación', 5,
 '["El error más común no es dar mala devolución: es empezar por el tercer peldaño. Se abre con la inquietud, y todo lo que viene después el alumno ya no lo escucha.","<strong>Clarificar</strong> es preguntar antes de suponer. <strong>Valorar</strong> es nombrar con precisión qué funcionó — no <em>muy bien</em>, sino qué específicamente resolvió bien. Recién ahí <strong>expresar inquietudes</strong>, en forma de pregunta y no de sentencia. Y cerrar con <strong>sugerir</strong>: un paso concreto, uno solo.","La escalera vale igual entre adultos. En las observaciones de clase entre pares usamos la misma estructura, y es la razón por la que funcionan."]'::jsonb,
 '[["Escalera y Pirámide de retroalimentación","PDF · 4 páginas"],["Registro de la jornada de marzo","Video · 14 min"]]'::jsonb,
 '{"p":"Un alumno entrega un informe desordenado pero con una hipótesis muy buena. ¿Cómo abrís la devolución?","op":["Está desordenado, cuesta seguirlo.","¿Por qué elegiste organizarlo así? Quiero entender tu criterio antes de comentarte.","Buen intento, seguí así.","Te faltó respetar el formato pedido."],"ok":1}'::jsonb,
 now() - interval '5 months', false),

('Uso de IA en trabajos de alumnos',
 'Qué está permitido, qué no, y cómo pedir que declaren el uso sin convertirlo en una cacería.',
 'Dirección', 'Acuerdo institucional', 7,
 '["El acuerdo parte de un supuesto: <strong>los alumnos ya la usan</strong>. La pregunta no es si prohibirla sino qué consigna sigue teniendo sentido.","Se permite el uso declarado para explorar ideas, corregir redacción y traducir. No se permite entregar como propio un texto generado sin intervención.","La declaración se pide en una línea al final del trabajo. No hace falta detector: si la consigna exige algo que la herramienta no puede hacer sola —vincular con lo trabajado en clase, usar datos del propio grupo, sostener una postura frente a un compañero— el problema se reduce solo."]'::jsonb,
 '[["Acuerdo de uso de IA · versión 2","PDF · 3 páginas"],["Consignas reformuladas por área","PDF"]]'::jsonb,
 '{"p":"¿Cuál es la estrategia que el acuerdo prioriza?","op":["Usar detectores de texto generado.","Prohibir la herramienta en todas las materias.","Reformular la consigna para que exija algo propio del curso.","Pedir que los trabajos se hagan a mano."],"ok":2}'::jsonb,
 now() - interval '4 months', false),

('El Eco Code no es un cartel en la pared',
 'Cómo se traduce el compromiso ambiental de Austin en decisiones concretas de aula, área por área.',
 'Gestión Ambiental', 'Gestión Ambiental', 4,
 '["El Eco Code se sostiene si aparece en la planificación, no solo en las efemérides. Una unidad de Matemática puede medir el consumo real del edificio; una de Lengua puede trabajar el discurso ambiental en la publicidad.","Lo que pedimos es concreto: <strong>al menos un PUD por área y por trimestre</strong> con una conexión ambiental explícita, declarada en el campo correspondiente.","No se trata de forzar el tema. Se trata de que la escuela que dice ser eco lo demuestre en lo que enseña, no solo en cómo separa los residuos."]'::jsonb,
 '[["Eco Code · Austin","PDF · 1 página"],["Ejemplos de conexión por área","PDF · 5 páginas"]]'::jsonb,
 '{"p":"¿Qué se pide concretamente a cada área?","op":["Participar del día del medio ambiente.","Al menos un PUD por trimestre con conexión ambiental declarada.","Separar residuos en el aula.","Sumarse al proyecto de huerta."],"ok":1}'::jsonb,
 now() - interval '3 months', false),

('Planificar la evaluación antes que la secuencia',
 'Si sabés qué vas a mirar para decir que comprendieron, la secuencia se ordena sola. Cinco minutos y una situación para resolver.',
 'Coordinación Pedagógica', 'Evaluación', 5,
 '["La secuencia más común es: pensar las actividades, darlas, y recién al final preguntarse cómo evaluar. Eso produce evaluaciones que miden otra cosa que la que se enseñó.","Invertirlo cuesta poco. Antes de diseñar la primera clase, escribí <strong>qué tendría que poder hacer un alumno</strong> para que digas que comprendió. Una oración.","Esa oración es después el criterio de evaluación continua, y de paso descarta la mitad de las actividades que ibas a poner, porque no llevan a ningún lado. En el PUD, es la bisagra entre las metas y los desempeños."]'::jsonb,
 '[["Evaluación en Austin","PDF · 5 páginas"],["Plantilla de criterio único","PDF · 1 página"],["Charla interna","Video · 9 min"]]'::jsonb,
 '{"p":"Según la cápsula, ¿cuándo conviene definir el criterio de evaluación?","op":["Al terminar la unidad, con lo que efectivamente se dio.","Antes de diseñar la primera clase.","En la mitad, cuando ya ves cómo viene el grupo.","Cuando lo pide Coordinación."],"ok":1}'::jsonb,
 now(), false),

('Tecnología e IA con propósito pedagógico',
 'Primero la intención pedagógica, después la herramienta. Para diseñar, crear e investigar — y para pensar con más criterio, no menos.',
 'Coordinación Pedagógica', 'Tecnología e IA', 6,
 '["La pregunta que abre cualquier uso de IA en el aula no es <em>qué herramienta</em> sino <em>qué quiero que mis alumnos comprendan o puedan hacer</em>. Recién después tiene sentido preguntarse si alguna herramienta ayuda a lograrlo mejor — y cuánto: sustituir un buscador por un chat no cambia la clase, pero rediseñar la consigna para que la IA sea parte del proceso de pensar, sí.","Bien usada, la IA generativa ayuda a <strong>diseñar</strong> consignas y variantes para distintos niveles, <strong>crear</strong> materiales y ejemplos, <strong>investigar</strong> más rápido y <strong>potenciar el pensamiento</strong> propio y el de los alumnos — probar una idea, pedir una objeción, mirar un problema desde otro ángulo. En todos los casos la herramienta propone y el docente decide: nada de lo que genera se usa sin revisión.","Lo mismo que se le pide a un alumno —declarar el uso, no entregar como propio lo que no pensó— vale para nosotros: ser transparentes sobre cuándo y cómo se usó IA en un material, y enseñar a cuestionar lo que produce en vez de aceptarlo directo. Los alumnos aprenden más de cómo un docente usa la IA delante de ellos que de cualquier acuerdo firmado."]'::jsonb,
 '[["Criterios de uso de IA para docentes · Austin","PDF · 2 páginas"],["Ejemplos: consignas rediseñadas con apoyo de IA","PDF · 4 páginas"]]'::jsonb,
 '{"p":"Un docente usa IA para generar tres variantes de la misma consigna, adaptadas a distintos niveles del curso, y las revisa antes de usarlas. ¿Qué principio está aplicando?","op":["Sustituir su planificación por la de la IA","Usar la herramienta para diseñar mejor, sin delegarle la decisión final","Evitar cualquier uso de IA en la planificación","Dejar que la IA elija qué consigna usar con cada estudiante"],"ok":1}'::jsonb,
 now(), false),

('Protocolo de ausentismo y señales de alerta',
 'Programada. Se publica el primer lunes del mes que viene.',
 'Equipo de Orientación', 'Protocolo', 5,
 '[]'::jsonb, '[]'::jsonb, null,
 now() + interval '1 month', true);

insert into public.encuestas (titulo, preguntas, abierta, cierra_en)
values
('Clima de trabajo · corte de mitad de año',
 '[{"t":"escala","p":"¿Cómo calificarías la comunicación entre Coordinación y tu área?","min":1,"max":5},{"t":"opciones","p":"¿Qué necesitás con más urgencia para tu trabajo diario?","op":["Más tiempo de planificación","Recursos materiales","Acompañamiento en el aula","Claridad en los criterios"]},{"t":"abierta","p":"Una cosa que cambiarías del funcionamiento de este trimestre"}]'::jsonb,
 true, now() + interval '7 days'),
('Necesidades de capacitación para el ciclo próximo',
 '[{"t":"opciones","p":"¿Qué tema priorizarías para la próxima capacitación?","op":["Evaluación formativa","Uso pedagógico de IA","Convivencia y conflicto","Inclusión y adecuaciones"]}]'::jsonb,
 false, now() - interval '30 days');
