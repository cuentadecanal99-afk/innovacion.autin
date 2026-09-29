-- =========================================================
-- Migración: endurecimiento general + sincronización del Onboarding
-- Aplicada el 2026-09-28. Idempotente: se puede volver a correr.
--
-- 1. Onboarding: onboarding_steps tenía 20 pasos de una versión vieja y
--    el sendero actual (ONBOARDING AUSTIN/index.html) tiene 50. Como
--    user_progress.step_id es FK a onboarding_steps, completar cualquier
--    paso que no estaba en la tabla fallaba (docentes trabados en t3-s5)
--    y los % de Al Día / Panel de Dirección se calculaban sobre 20.
--    Los pasos viejos no se borran (borrarían progreso por cascade): se
--    marcan activo = false y dejan de contar.
-- 2. PUDs: la lectura de PUDs presentados pasa a respetar los permisos de
--    grado/materia de cada coordinador EN LA BASE (antes cualquier usuario
--    logueado podía leer todos). El docente ya no puede auto-aprobarse.
-- 3. Al Día: la fecha de confirmación y si la respuesta fue correcta los
--    fija la base, no el navegador. El seguimiento incluye a todo el
--    staff autorizado, no solo a quien ya abrió Al Día.
-- 4. Limpieza: policies duplicadas, funciones sin search_path, funciones
--    internas que el rol anónimo podía ejecutar, escalada de rol en perfiles.
--
-- Si se agregan pasos nuevos al Onboarding, hay que sumarlos también
-- acá (onboarding_steps), o completar_paso() los va a rechazar.
-- =========================================================

-- ---------------------------------------------------------
-- 1. ONBOARDING
-- ---------------------------------------------------------
alter table public.onboarding_steps add column if not exists activo boolean not null default true;

insert into public.onboarding_topics (id, title, icon, description, order_index) values
  ('topic-1', 'Bienvenida a Austin', '🏫', 'Quiénes somos, el equipo de Secundario y cómo trabajamos juntos.', 0),
  ('topic-2', 'Enseñanza para la Comprensión (EpC)', '🧠', 'El gran marco de diseño pedagógico: comprensión, metas, desempeños, transferencia y valoración continua.', 1),
  ('topic-3', 'Valoración continua', '📊', 'Criterios visibles, evidencias de comprensión, feedback, rúbricas, autoevaluación y revisión del propio proceso.', 2),
  ('topic-cultura-pensamiento', 'Cultura de Pensamiento', '💭', 'Pensamiento visible, rutinas de pensamiento, disposiciones y fuerzas culturales.', 3),
  ('topic-sel', 'Educación Emocional y Social', '❤️', 'Autoconocimiento, regulación emocional, empatía, vínculos, habilidades sociales y clima para aprender.', 4),
  ('topic-disciplina-positiva', 'Disciplina Positiva y Convivencia', '🧭', 'Firmeza y amabilidad, conexión antes que corrección, límites, acuerdos, conflicto, reflexión y reparación.', 5),
  ('topic-agencia', 'Agency by Design y Agencia del Estudiante', '🛠️', 'Voz, elección, autonomía, toma de decisiones y capacidad de transformar el entorno — y qué hace (o deja de hacer) el docente para habilitarla.', 6),
  ('topic-neurodiversidad', 'Neurodiversidad: cómo aprende el cerebro', '🧩', 'Atención, memoria, funciones ejecutivas, motivación, carga cognitiva, recuperación, consolidación y condiciones que favorecen el aprendizaje.', 7),
  ('topic-steam', 'STEAM e Innovación', '🧪', 'Integración de disciplinas, resolución de problemas, creatividad, diseño, experimentación, prototipado y aprendizaje a partir del error.', 8),
  ('topic-bilinguismo', 'Bilingüismo', '🗣️', 'Que el idioma se escuche, se use y se respire en la vida cotidiana del colegio — un compromiso de todo el equipo, no solo de los docentes de inglés.', 9),
  ('topic-4', 'Eco-Schools y Educación Ambiental', '🌱', 'Sustentabilidad, conciencia ambiental, participación, acción y coherencia entre lo que se enseña y las prácticas institucionales.', 10),
  ('topic-ia', 'Tecnología e IA con propósito pedagógico', '🤖', 'Primero la intención pedagógica, después la herramienta — IA para diseñar, crear e investigar, con autoría, pensamiento crítico y criterios de uso.', 11),
  ('topic-proyecto-institucional', 'Proyecto Institucional', '🎯', 'El proyecto que atraviesa este ciclo — se actualiza cada vez que cambia.', 12),
  ('topic-5', 'Este ciclo lectivo', '📅', 'Novedades y fechas importantes — este contenido se actualiza cada año.', 13)
on conflict (id) do update set title = excluded.title, icon = excluded.icon, description = excluded.description, order_index = excluded.order_index;

insert into public.onboarding_steps (id, topic_id, title, xp, step_type, order_index, activo) values
  ('t1-s1', 'topic-1', 'Quiénes somos', 20, 'quiz', 0, true),
  ('t1-s2', 'topic-1', 'El equipo de Secundario', 20, 'quiz', 1, true),
  ('t1-s3', 'topic-1', 'Cómo nos comunicamos con las familias', 20, 'quiz', 2, true),
  ('t1-s4', 'topic-1', 'Organización del tiempo y del aula', 20, 'quiz', 3, true),
  ('t1-s5', 'topic-1', 'Reglamento interno', 20, 'quiz', 4, true),
  ('t2-s1', 'topic-2', '¿Qué es comprender?', 25, 'quiz', 0, true),
  ('t2-s2', 'topic-2', 'Los 4 elementos del marco EpC', 25, 'quiz', 1, true),
  ('t2-s3', 'topic-2', 'EpC vs. enseñanza tradicional', 25, 'quiz', 2, true),
  ('t2-s4', 'topic-2', 'Practicá: armar un PUD (parte 1)', 30, 'quiz', 3, true),
  ('t2-s5', 'topic-2', 'Practicá: armar un PUD (parte 2)', 30, 'quiz', 4, true),
  ('t2-s6', 'topic-2', 'La Planificación Anual', 20, 'quiz', 5, true),
  ('t3-s1', 'topic-3', 'Cómo evaluamos en Austin', 20, 'quiz', 0, true),
  ('t3-s2', 'topic-3', 'Técnicas de evaluación y devolución', 20, 'quiz', 1, true),
  ('t3-s3', 'topic-3', 'La Escalera de la Retroalimentación', 25, 'quiz', 2, true),
  ('t3-s4', 'topic-3', 'La Pirámide de la Retroalimentación', 20, 'quiz', 3, true),
  ('t3-s5', 'topic-3', 'Criterios visibles y autoevaluación', 25, 'quiz', 4, true),
  ('tcp-s1', 'topic-cultura-pensamiento', '¿Qué es una Cultura de Pensamiento?', 20, 'quiz', 0, true),
  ('tcp-s2', 'topic-cultura-pensamiento', 'Las 8 fuerzas culturales', 20, 'quiz', 1, true),
  ('tcp-s3', 'topic-cultura-pensamiento', 'Rutinas de pensamiento', 20, 'quiz', 2, true),
  ('tcp-s4', 'topic-cultura-pensamiento', 'Hacerlo parte de tu aula', 25, 'quiz', 3, true),
  ('tsel-s1', 'topic-sel', '¿Por qué importa lo emocional para aprender?', 20, 'quiz', 0, true),
  ('tsel-s2', 'topic-sel', 'Las 5 competencias socioemocionales', 25, 'quiz', 1, true),
  ('tsel-s3', 'topic-sel', 'Autorregulación en el aula', 20, 'quiz', 2, true),
  ('tsel-s4', 'topic-sel', 'Vínculos y clima para aprender', 20, 'quiz', 3, true),
  ('tdp-s1', 'topic-disciplina-positiva', 'Firmeza y amabilidad, a la vez', 20, 'quiz', 0, true),
  ('tdp-s2', 'topic-disciplina-positiva', 'Conexión antes que corrección', 20, 'quiz', 1, true),
  ('tdp-s3', 'topic-disciplina-positiva', 'Límites y acuerdos, no solo reglas impuestas', 20, 'quiz', 2, true),
  ('tdp-s4', 'topic-disciplina-positiva', 'Conflicto: reflexión y reparación', 25, 'quiz', 3, true),
  ('tag-s1', 'topic-agencia', '¿Qué es la agencia?', 20, 'quiz', 0, true),
  ('tag-s2', 'topic-agencia', 'Las 3 capacidades de Agency by Design', 25, 'quiz', 1, true),
  ('tag-s3', 'topic-agencia', 'Qué hace (o deja de hacer) el docente', 25, 'quiz', 2, true),
  ('tnd-s1', 'topic-neurodiversidad', 'Neurodiversidad: variación, no déficit', 20, 'quiz', 0, true),
  ('tnd-s2', 'topic-neurodiversidad', 'Memoria de trabajo y carga cognitiva', 20, 'quiz', 1, true),
  ('tnd-s3', 'topic-neurodiversidad', 'Funciones ejecutivas', 20, 'quiz', 2, true),
  ('tnd-s4', 'topic-neurodiversidad', 'Diseñar para que aprenda cualquier cerebro', 25, 'quiz', 3, true),
  ('tsteam-s1', 'topic-steam', 'Qué es STEAM (y qué no es)', 20, 'quiz', 0, true),
  ('tsteam-s2', 'topic-steam', 'El proceso de diseño', 25, 'quiz', 1, true),
  ('tsteam-s3', 'topic-steam', 'El error como parte del proceso', 20, 'quiz', 2, true),
  ('tbil-s1', 'topic-bilinguismo', 'Un entorno bilingüe, no solo una materia', 20, 'quiz', 0, true),
  ('tbil-s2', 'topic-bilinguismo', 'El compromiso según tu rol', 20, 'quiz', 1, true),
  ('tbil-s3', 'topic-bilinguismo', 'Cómo sumar desde cualquier materia', 20, 'quiz', 2, true),
  ('t4-s1', 'topic-4', 'Nuestro Eco Code', 15, 'quiz', 0, true),
  ('t4-s2', 'topic-4', 'La metodología Eco-Schools', 20, 'quiz', 1, true),
  ('t4-s3', 'topic-4', 'Tu rol en el aula', 20, 'quiz', 2, true),
  ('tia-s1', 'topic-ia', 'La intención antes que la herramienta', 20, 'quiz', 0, true),
  ('tia-s2', 'topic-ia', 'IA generativa: qué habilita y qué arriesga', 25, 'quiz', 1, true),
  ('tia-s3', 'topic-ia', 'Autoría, pensamiento crítico y criterios de uso', 20, 'quiz', 2, true),
  ('tpi-s1', 'topic-proyecto-institucional', '"Every Step Matters"', 20, 'quiz', 0, true),
  ('tpi-s2', 'topic-proyecto-institucional', 'Tu rol en el proyecto institucional', 20, 'quiz', 1, true),
  ('t5-s1', 'topic-5', 'Novedades y fechas 2026', 10, 'info', 0, true)
on conflict (id) do update set topic_id = excluded.topic_id, title = excluded.title, xp = excluded.xp, step_type = excluded.step_type, order_index = excluded.order_index, activo = true;

update public.onboarding_steps set activo = false where id not in ('t1-s1', 't1-s2', 't1-s3', 't1-s4', 't1-s5', 't2-s1', 't2-s2', 't2-s3', 't2-s4', 't2-s5', 't2-s6', 't3-s1', 't3-s2', 't3-s3', 't3-s4', 't3-s5', 'tcp-s1', 'tcp-s2', 'tcp-s3', 'tcp-s4', 'tsel-s1', 'tsel-s2', 'tsel-s3', 'tsel-s4', 'tdp-s1', 'tdp-s2', 'tdp-s3', 'tdp-s4', 'tag-s1', 'tag-s2', 'tag-s3', 'tnd-s1', 'tnd-s2', 'tnd-s3', 'tnd-s4', 'tsteam-s1', 'tsteam-s2', 'tsteam-s3', 'tbil-s1', 'tbil-s2', 'tbil-s3', 't4-s1', 't4-s2', 't4-s3', 'tia-s1', 'tia-s2', 'tia-s3', 'tpi-s1', 'tpi-s2', 't5-s1');

create or replace function public.completar_paso(p_step_id text, p_answers jsonb)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_user_id uuid := auth.uid();
    v_total int;
    v_correctas int;
begin
    if v_user_id is null then
        raise exception 'No autenticado';
    end if;

    -- Solo pasos del sendero actual: evita inflar el progreso con
    -- step_id inventados o de la versión vieja.
    if not exists (select 1 from onboarding_steps where id = p_step_id and activo) then
        raise exception 'Paso inexistente: %', p_step_id;
    end if;

    select count(*) into v_total
    from quiz_answers
    where step_id = p_step_id;

    if v_total > 0 then
        select count(*) into v_correctas
        from quiz_answers qa
        where qa.step_id = p_step_id
          and (p_answers ->> qa.question_id)::int = qa.correct_index;

        if v_correctas < v_total then
            return false;
        end if;
    end if;

    insert into user_progress (user_id, step_id, completed_at)
    values (v_user_id, p_step_id, now())
    on conflict (user_id, step_id) do update set completed_at = excluded.completed_at;

    return true;
end;
$function$;

create or replace function public.director_onboarding_overview()
returns table(user_id uuid, email text, completed_steps bigint, total_steps bigint, pct numeric)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select
    u.id as user_id,
    u.email::text,
    coalesce(p.completed_steps, 0) as completed_steps,
    t.total_steps,
    round(coalesce(p.completed_steps, 0)::numeric / nullif(t.total_steps, 0) * 100, 1) as pct
  from auth.users u
  cross join (select count(*)::bigint as total_steps from public.onboarding_steps where activo) t
  left join (
    select up.user_id, count(*)::bigint as completed_steps
    from public.user_progress up
    join public.onboarding_steps s on s.id = up.step_id and s.activo
    group by up.user_id
  ) p on p.user_id = u.id
  where exists (select 1 from public.directores d where d.email = lower(auth.jwt() ->> 'email'))
    and (p.completed_steps is not null or lower(u.email) in (select lower(email) from public.allowed_emails))
  order by pct desc nulls last, u.email asc;
$function$;

-- ---------------------------------------------------------
-- 2. PUDs
-- ---------------------------------------------------------
-- ¿El usuario logueado es coordinador y tiene permiso sobre este grado y
-- materia? Sin filas en coordinador_permiso_* = sin restricción en ese
-- eje (mismo criterio que tieneAcceso() en coordinadores/index.html).
create or replace function public.coordinador_puede_ver(p_year text, p_subject text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  with yo as (select lower(trim(auth.jwt() ->> 'email')) as email)
  select exists (select 1 from coordinadores c, yo where c.email = yo.email)
    and (
      not exists (select 1 from coordinador_permiso_grados g, yo where g.email = yo.email)
      or exists (select 1 from coordinador_permiso_grados g, yo where g.email = yo.email and g.grado = p_year)
    )
    and (
      not exists (select 1 from coordinador_permiso_materias m, yo where m.email = yo.email)
      or exists (select 1 from coordinador_permiso_materias m, yo where m.email = yo.email and m.materia = p_subject)
    );
$function$;

drop policy if exists pud_history_select_presented_public on public.pud_history;
drop policy if exists pud_history_select_coordinador on public.pud_history;
create policy pud_history_select_coordinador on public.pud_history
  for select to authenticated
  using (status = 'presented' and public.coordinador_puede_ver(year, subject));

-- Policies duplicadas (mismo efecto que otra ya existente).
drop policy if exists "Users can insert own PUDs" on public.pud_history;
drop policy if exists "Users can view own PUDs" on public.pud_history;
drop policy if exists "Users can update own PUDs" on public.pud_history;

-- Los campos de revisión solo los escribe revisar_pud_presentado(): un
-- docente no puede insertar ni editar su PUD como "approved".
create or replace function public.proteger_revision_pud()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if coalesce(current_setting('app.revision_pud', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.review_status := 'pending';
    new.review_comment := null;
    new.reviewed_at := null;
  elsif new.review_status is distinct from old.review_status
     or new.review_comment is distinct from old.review_comment
     or new.reviewed_at is distinct from old.reviewed_at then
    raise exception 'Solo coordinación puede cambiar la revisión de un PUD';
  end if;
  return new;
end;
$function$;

drop trigger if exists proteger_revision_pud on public.pud_history;
create trigger proteger_revision_pud
  before insert or update on public.pud_history
  for each row execute function public.proteger_revision_pud();

create or replace function public.revisar_pud_presentado(p_id uuid, p_review_status text, p_review_comment text default null)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if p_review_status not in ('approved', 'changes_requested') then
    raise exception 'review_status inválido: %', p_review_status;
  end if;

  if p_review_status = 'changes_requested' and coalesce(trim(p_review_comment), '') = '' then
    raise exception 'Hay que indicar un comentario al solicitar cambios';
  end if;

  perform set_config('app.revision_pud', 'on', true);

  update public.pud_history
  set review_status = p_review_status,
      review_comment = case when p_review_status = 'approved' then null else trim(p_review_comment) end,
      reviewed_at = now()
  where id = p_id
    and status = 'presented'
    and public.coordinador_puede_ver(year, subject);

  if not found then
    raise exception 'PUD no encontrado, no presentado o fuera de tus permisos';
  end if;

  perform set_config('app.revision_pud', '', true);
end;
$function$;

-- ---------------------------------------------------------
-- 3. AL DÍA
-- ---------------------------------------------------------
create or replace function public.sellar_confirmacion_capsula()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  new.confirmado_at := now();
  new.correcta := new.respuesta_index is not null
    and new.respuesta_index = (select (k.chequeo ->> 'ok')::int from capsulas k where k.id = new.capsula_id);
  return new;
end;
$function$;

drop trigger if exists sellar_confirmacion_capsula on public.capsula_confirmaciones;
create trigger sellar_confirmacion_capsula
  before insert or update on public.capsula_confirmaciones
  for each row execute function public.sellar_confirmacion_capsula();

create or replace function public.aldia_seguimiento_capsulas()
returns table(user_id uuid, email text, capsula_id uuid, estado text, confirmado_at timestamp with time zone)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with autorizado as (
    select
      exists (select 1 from public.coordinadores c where c.email = lower(auth.jwt() ->> 'email'))
      or exists (select 1 from public.directores d where d.email = lower(auth.jwt() ->> 'email'))
      as ok
  ),
  -- Todo el staff autorizado (aunque nunca haya abierto Al Día) más quien
  -- ya interactuó: antes, los que nunca entraron no figuraban como "faltan".
  personas as (
    select u.id as user_id from auth.users u
    where lower(u.email) in (select lower(email) from public.allowed_emails)
    union
    select user_id from public.capsula_confirmaciones
    union
    select user_id from public.encuesta_respuestas
  )
  select
    u.id as user_id,
    u.email::text,
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
$function$;

-- ---------------------------------------------------------
-- 4. LIMPIEZA DE SEGURIDAD
-- ---------------------------------------------------------
-- Funciones que solo tienen sentido con sesión iniciada (o que son
-- triggers): el rol anónimo ya no puede llamarlas por /rest/v1/rpc.
revoke execute on function public.completar_paso(text, jsonb) from public, anon;
revoke execute on function public.director_onboarding_overview() from public, anon;
revoke execute on function public.revisar_pud_presentado(uuid, text, text) from public, anon;
revoke execute on function public.aldia_seguimiento_capsulas() from public, anon;
revoke execute on function public.coordinador_puede_ver(text, text) from public, anon;
revoke execute on function public.crear_perfil_nuevo_usuario() from public, anon, authenticated;
revoke execute on function public.validar_correo_autorizado() from public, anon, authenticated;
revoke execute on function public.sellar_confirmacion_capsula() from public, anon, authenticated;
revoke execute on function public.proteger_revision_pud() from public, anon, authenticated;
grant execute on function public.completar_paso(text, jsonb) to authenticated;
grant execute on function public.director_onboarding_overview() to authenticated;
grant execute on function public.revisar_pud_presentado(uuid, text, text) to authenticated;
grant execute on function public.aldia_seguimiento_capsulas() to authenticated;
grant execute on function public.coordinador_puede_ver(text, text) to authenticated;

alter function public.validar_correo_autorizado() set search_path = public;
alter function public.areas_nombre_normalizado(text) set search_path = public;
alter function public.get_random_questions(text, integer) set search_path = public;
alter function public.evaluar_test(text, jsonb) set search_path = public;
alter function public.evaluar_test_adaptativo(jsonb) set search_path = public;

-- perfiles: la policy de UPDATE no tenía WITH CHECK, así que cualquier
-- usuario podía ponerse rol = 'admin'. Ahora solo puede editar su nombre.
revoke update on public.perfiles from anon, authenticated;
grant update (nombre) on public.perfiles to authenticated;

-- La policy "admin ve todos los perfiles" consultaba perfiles desde
-- perfiles (recursión infinita en Postgres). Se reemplaza por una función.
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (select 1 from perfiles where id = auth.uid() and rol = 'admin');
$function$;
revoke execute on function public.es_admin() from public, anon;
grant execute on function public.es_admin() to authenticated;
drop policy if exists "admin ve todos los perfiles" on public.perfiles;
create policy "admin ve todos los perfiles" on public.perfiles
  for select to authenticated using (public.es_admin());

-- resultados estaba sin RLS: con la anon key se podía leer, editar o
-- borrar la tabla entera. Cada usuario ve y carga solo lo suyo.
alter table public.resultados enable row level security;
drop policy if exists resultados_select_own on public.resultados;
create policy resultados_select_own on public.resultados
  for select to authenticated using (user_id = auth.uid());
drop policy if exists resultados_insert_own on public.resultados;
create policy resultados_insert_own on public.resultados
  for insert to authenticated with check (user_id = auth.uid());
