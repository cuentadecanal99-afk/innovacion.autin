# Setup de Supabase — Sendero de Bienvenida

> **Estado actual del archivo:** `index.html` viene con `DEMO_MODE = true`,
> así que ahora mismo funciona 100% sin Supabase — el login acepta cualquier
> correo/contraseña y el progreso se guarda en el navegador (`localStorage`).
> Es para que puedas probar la UX y la gamificación ya mismo. Este documento
> es la guía para cuando quieras conectar el backend real.

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
    email text primary key,
    agregado_por text,
    created_at timestamptz default now()
);

alter table allowed_emails enable row level security;

-- Cualquier usuario (incluso anónimo) puede LEER la lista para validar
-- si su correo está autorizado antes de registrarse.
create policy "lectura publica de allowed_emails"
on allowed_emails for select
using (true);

-- Nadie puede insertar/editar desde el cliente; se carga a mano
-- desde el SQL Editor o el dashboard de Supabase.
```

Cargá los correos del staff, por ejemplo:

```sql
insert into allowed_emails (email, agregado_por) values
('nombre.apellido@austineco.edu.ar', 'coordinacion'),
('otra.persona@austineco.edu.ar', 'coordinacion');
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

create policy "usuarios insertan su propio progreso"
on user_progress for insert
with check (auth.uid() = user_id);

create policy "usuarios actualizan su propio progreso"
on user_progress for update
using (auth.uid() = user_id);
```

El `unique (user_id, step_id)` es lo que permite que el `upsert` del front
funcione sin duplicar filas si alguien vuelve a marcar el mismo paso.

## 4. (Opcional) Contenido editable desde el backend

Por defecto, `index.html` trae el contenido de los 3 tópicos y sus 5 pasos
hardcodeado en el arreglo `ONBOARDING_STRUCTURE` dentro del `<script>`, en
formato markdown. Es la forma más simple de arrancar: editás el texto
directamente en el archivo.

Si más adelante querés que el contenido sea editable sin tocar código (por
ejemplo, para que coordinación cargue textos desde el dashboard de Supabase),
creá estas dos tablas — el front ya intenta leerlas automáticamente y usa el
arreglo local solo como respaldo si no las encuentra:

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
                       -- { "type": "quiz", "passing_score": 2, "questions": [ { "id": "q1", "text": "...", "options": ["A","B","C"], "correct_index": 0 } ] }
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
| `onboarding_topics` / `onboarding_steps` | No | Solo si querés editar contenido sin tocar código |
