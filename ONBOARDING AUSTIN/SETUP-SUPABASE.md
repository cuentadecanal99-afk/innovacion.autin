# Setup de Supabase — Sendero de Bienvenida

> **Estado actual del archivo:** `index.html` ya tiene `DEMO_MODE = false` y
> credenciales reales de Supabase cargadas — está conectado al backend real,
> no al modo demo. Este documento sigue sirviendo como referencia del
> esquema (tablas, políticas RLS, funciones) por si necesitás recrearlo en
> otro proyecto de Supabase, o entender cómo funciona el que ya está armado.

Estas son las tablas y políticas necesarias para que `index.html` funcione
contra Supabase de verdad. Corré estos bloques desde el **SQL Editor** de tu
proyecto, en orden.

## 0. Pasar de modo demo a modo real

Cuando tengas todo lo de abajo armado, en `index.html` cambiá:

```js
const DEMO_MODE = false;
```

y completá:

```js
const SUPABASE_URL = 'https://tu-proyecto-real.supabase.co';
const SUPABASE_KEY = 'tu-anon-key-real';
```

(Los valores están en **Project Settings → API** de tu proyecto Supabase.)

## 1. Lista de correos autorizados por el colegio

Controla quién puede crear una cuenta. El front chequea esta tabla antes de
llamar a `signUp`, pero **eso solo es una validación de UX** — cualquiera con
las devtools abiertas podría saltearla. La protección real está en el paso 2
(trigger a nivel de base de datos).

```sql
create table allowed_emails (
    email text primary key
);

alter table allowed_emails enable row level security;

-- Sin policies de SELECT/INSERT/UPDATE/DELETE a propósito: la tabla queda
-- completamente cerrada al cliente (anon/authenticated). Se carga a mano
-- desde el SQL Editor o el dashboard de Supabase (esa sesión no pasa por
-- RLS). El chequeo de "¿mi correo está autorizado?" se hace vía la función
-- de abajo, que devuelve solo true/false — así el cliente nunca puede
-- listar la tabla completa de correos del staff con la anon key.
```

Cargá los correos del staff, por ejemplo:

```sql
insert into allowed_emails (email) values
('nombre.apellido@austineco.edu.ar'),
('otra.persona@austineco.edu.ar');
```

Función que el front usa para validar un correo sin exponer la tabla
(`security definer` = corre con permisos del dueño de la función, así que
puede leer `allowed_emails` aunque no haya ninguna policy de SELECT):

```sql
create or replace function public.correo_autorizado(p_email text)
returns boolean
language sql
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.allowed_emails
        where lower(email) = lower(p_email)
    );
$$;

revoke all on function public.correo_autorizado(text) from public;
grant execute on function public.correo_autorizado(text) to anon, authenticated;
```

## 2. (Recomendado) Trigger que bloquea el registro a nivel de base

Esto asegura que, aunque alguien evite el chequeo del front, Supabase
**rechace el `signUp`** si el correo no está en `allowed_emails`.

```sql
create or replace function public.validar_correo_autorizado()
returns trigger as $$
begin
    if not exists (
        select 1 from public.allowed_emails
        where lower(email) = lower(new.email)
    ) then
        raise exception 'Correo no autorizado por el colegio: %', new.email;
    end if;
    return new;
end;
$$ language plpgsql security definer;

create trigger antes_de_crear_usuario
before insert on auth.users
for each row execute function public.validar_correo_autorizado();
```

> Si en algún momento querés desactivar temporalmente esta validación
> (por ejemplo, para pruebas), podés borrar el trigger con
> `drop trigger antes_de_crear_usuario on auth.users;` y volver a crearlo después.

## 3. Progreso por usuario

```sql
create table user_progress (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) not null,
    step_id text not null,
    completed_at timestamptz default now(),
    unique (user_id, step_id)
);

alter table user_progress enable row level security;

create policy "usuarios ven su propio progreso"
on user_progress for select
using (auth.uid() = user_id);

-- A propósito NO hay policy de INSERT ni de UPDATE para el cliente.
-- Si las hubiera, cualquier usuario autenticado podría hacer
-- supabase.from('user_progress').upsert({ step_id: 'cualquiera' }) desde
-- la consola y completar pasos sin responder nada. La única forma de
-- escribir en esta tabla es a través de la función completar_paso()
-- de abajo (security definer), que primero valida el quiz.
```

El `unique (user_id, step_id)` es lo que permite que el upsert interno de
`completar_paso()` funcione sin duplicar filas si alguien vuelve a marcar
el mismo paso.

### Respuestas correctas del quiz (nunca viajan al cliente)

Antes, `correct_index` vivía directamente en el arreglo `ONBOARDING_STRUCTURE`
del `<script>` de `index.html` — visible con "Ver código fuente", sin ni
siquiera abrir devtools. Ahora las respuestas correctas se guardan en una
tabla cerrada al cliente, igual que `allowed_emails`:

```sql
create table quiz_answers (
    step_id text not null,
    question_id text not null,
    correct_index int not null,
    primary key (step_id, question_id)
);

alter table quiz_answers enable row level security;

-- Sin policies de SELECT/INSERT/UPDATE/DELETE a propósito: la tabla queda
-- completamente cerrada al cliente. Solo la lee completar_paso() (más
-- abajo), que corre con security definer.
```

Cargá las respuestas correctas (una fila por pregunta; `question_id` es el
mismo `id` que usás en `activity.questions` dentro de `index.html`):

```sql
insert into quiz_answers (step_id, question_id, correct_index) values
('t1-s1', 'q1', 1),
('t1-s2', 'q1', 1),
('t1-s3', 'q1', 1),
('t1-s4', 'q1', 0),
('t1-s5', 'q1', 1),
('t2-s1', 'q1', 1),
('t2-s2', 'q1', 2),
('t2-s3', 'q1', 2),
('t2-s4', 'q1', 1),
('t2-s5', 'q1', 2),
('t2-s6', 'q1', 1),
('tcp-s1', 'q1', 1),
('tcp-s2', 'q1', 0),
('tcp-s3', 'q1', 1),
('tcp-s4', 'q1', 1),
('t3-s1', 'q1', 1),
('t3-s2', 'q1', 1),
('t3-s3', 'q1', 1),
('t3-s4', 'q1', 1),
('t3-s5', 'q1', 2),
('tag-s1', 'q1', 1),
('tag-s2', 'q1', 1),
('tag-s3', 'q1', 1),
('tsel-s1', 'q1', 1),
('tsel-s2', 'q1', 1),
('tsel-s3', 'q1', 1),
('tsel-s4', 'q1', 1),
('tdp-s1', 'q1', 2),
('tdp-s2', 'q1', 1),
('tdp-s3', 'q1', 1),
('tdp-s4', 'q1', 1),
('tnd-s1', 'q1', 1),
('tnd-s2', 'q1', 1),
('tnd-s3', 'q1', 1),
('tnd-s4', 'q1', 1),
('tsteam-s1', 'q1', 1),
('tsteam-s2', 'q1', 1),
('tsteam-s3', 'q1', 1),
('tbil-s1', 'q1', 1),
('tbil-s2', 'q1', 1),
('tbil-s3', 'q1', 1),
('t4-s1', 'q1', 1),
('t4-s2', 'q1', 1),
('t4-s3', 'q1', 1),
('tia-s1', 'q1', 1),
('tia-s2', 'q1', 1),
('tia-s3', 'q1', 1),
('tpi-s1', 'q1', 1),
('tpi-s2', 'q1', 1);
```

> **Ojo:** tiene que haber exactamente una fila por `question_id` que
> exista en `activity.questions` de ese paso en `index.html` — ni una
> menos ni una de más. `completar_paso()` cuenta **todas** las filas de
> `quiz_answers` para el `step_id` (línea `select count(*) ... into v_total`)
> y las compara contra las respuestas que mandó el cliente; si queda una
> fila vieja de una pregunta que ya no existe en el front (por ejemplo, un
> `q2` que se borró del contenido pero no de esta tabla), `v_total` nunca
> baja y el paso se marca "incorrecto" pase lo que pase, aunque el
> usuario responda bien la única pregunta que sí ve. Si en algún momento
> el quiz vuelve a marcar todo como incorrecto sin motivo aparente, lo
> primero a revisar es que esta tabla tenga las mismas preguntas — ni más
> ni menos — que el `step.activity.questions` correspondiente.

Función que valida las respuestas de un paso y, si están todas correctas,
guarda el progreso — todo en una sola operación server-side (así el cliente
nunca ve `correct_index` ni puede saltarse la corrección llamando directo a
`user_progress`):

```sql
create or replace function public.completar_paso(p_step_id text, p_answers jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_total int;
    v_correctas int;
begin
    if v_user_id is null then
        raise exception 'No autenticado';
    end if;

    select count(*) into v_total
    from quiz_answers
    where step_id = p_step_id;

    -- Paso sin preguntas registradas (ej. step_type 'info', o un quiz
    -- placeholder todavía sin respuestas cargadas): se completa sin
    -- exigir nada, igual que el botón "Marcar como leído".
    if v_total = 0 then
        insert into user_progress (user_id, step_id, completed_at)
        values (v_user_id, p_step_id, now())
        on conflict (user_id, step_id) do update set completed_at = excluded.completed_at;
        return true;
    end if;

    select count(*) into v_correctas
    from quiz_answers qa
    where qa.step_id = p_step_id
      and (p_answers ->> qa.question_id)::int = qa.correct_index;

    if v_correctas < v_total then
        return false; -- alguna respuesta está mal (o falta): no se guarda nada
    end if;

    insert into user_progress (user_id, step_id, completed_at)
    values (v_user_id, p_step_id, now())
    on conflict (user_id, step_id) do update set completed_at = excluded.completed_at;

    return true;
end;
$$;

revoke all on function public.completar_paso(text, jsonb) from public;
grant execute on function public.completar_paso(text, jsonb) to authenticated;
```

> La regla actual es "hay que acertar todas las preguntas del paso"
> (coincide con que hoy `passing_score` siempre es igual a la cantidad de
> preguntas). Si en el futuro querés un `passing_score` parcial (ej.
> acertar 2 de 3), agregá una columna `passing_score` a una tabla de
> config por paso y cambiá el `if v_correctas < v_total` por la
> comparación contra ese valor.

## 4. (Deprecado) Contenido editable desde el backend

> **Estado actual:** `index.html` **ya no lee estas tablas**. Antes existía
> `intentarCargarContenidoDesdeSupabase()`, que reemplazaba en silencio el
> arreglo local `ONBOARDING_STRUCTURE` por lo que hubiera en
> `onboarding_topics`/`onboarding_steps` — eso causó que contenido viejo de
> estas tablas pisara la estructura nueva del código en cada login (los
> niveles, el orden y hasta el campo `standalone` volvían a la versión
> vieja, porque esta tabla ni siquiera tiene columna `standalone`). Se quitó
> esa lógica: `ONBOARDING_STRUCTURE` es ahora la única fuente de verdad de
> la estructura. Las tablas de abajo **no se borraron** (por si se decide
> migrar de verdad más adelante, con una migración explícita), pero el
> front ya no las consulta para construir la interfaz.

Por defecto, `index.html` trae el contenido de todos los tópicos y sus pasos
hardcodeado en el arreglo `ONBOARDING_STRUCTURE` dentro del `<script>`, en
formato markdown. Es la forma más simple de arrancar: editás el texto
directamente en el archivo, y es lo único que la app usa hoy.

Estas dos tablas quedan documentadas por si en el futuro se decide migrar el
contenido a Supabase de verdad (estructura editable sin tocar código) — pero
esa migración habría que hacerla a propósito, no reactivando el reemplazo
silencioso de antes:

```sql
create table onboarding_topics (
    id text primary key,
    title text not null,
    description text,
    icon text,
    order_index int not null
);

create table onboarding_steps (
    id text primary key,
    topic_id text references onboarding_topics(id) not null,
    title text not null,
    content_md text,
    media_type text,   -- youtube | vimeo | drive | video | audio | image | iframe
    media_url text,
    xp int default 20,
    quiz_json jsonb,   -- actividad de evaluación, mismo formato que `step.activity` en el front:
                       -- { "type": "quiz", "passing_score": 2, "questions": [ { "id": "q1", "text": "...", "options": ["A","B","C"] } ] }
                       -- OJO: acá NO va `correct_index` — esta tabla tiene lectura pública
                       -- (policy `using (true)`), así que cualquier respuesta correcta que
                       -- pusieras acá quedaría expuesta con la anon key. La respuesta
                       -- correcta de cada pregunta se carga aparte, en `quiz_answers`
                       -- (ver sección 3), con el mismo `step_id`/`question_id`.
    order_index int not null
);

alter table onboarding_topics enable row level security;
alter table onboarding_steps enable row level security;

create policy "lectura publica de topics" on onboarding_topics for select using (true);
create policy "lectura publica de steps" on onboarding_steps for select using (true);
```

## 5. Confirmación final

Con `DEMO_MODE = false` y las credenciales reales cargadas, el login ya
valida contra Supabase y el progreso se guarda en `user_progress` en vez de
en el navegador.

## Resumen de tablas

| Tabla | Obligatoria | Para qué |
|---|---|---|
| `allowed_emails` | Sí | Controla quién puede registrarse |
| `user_progress` | Sí | Guarda qué pasos completó cada usuario |
| `quiz_answers` | Sí | Respuestas correctas del quiz, cerrada al cliente |
| `onboarding_topics` / `onboarding_steps` | No (deprecado) | El front ya no las lee — ver nota en sección 4 |
