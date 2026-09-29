-- ═══════════════════════════════════════════════════════════════
-- Calendario institucional · Austin Eco Bilingual School
-- Reuniones y eventos cargados desde el Panel de Dirección General
-- (ALFA) y mostrados como calendario anual en el Panel de Bienvenida
-- de Espacio Docente.
-- ═══════════════════════════════════════════════════════════════

create table if not exists public.eventos_calendario (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descripcion text,
  fecha date not null,
  hora time,
  tipo text not null default 'evento'
    check (tipo in ('reunion','evento','feriado','entrega','otro')),
  creado_por text,
  created_at timestamptz not null default now()
);

create index if not exists eventos_calendario_fecha_idx on public.eventos_calendario (fecha);

-- ═══════════════════════════════════════════════════════════════
-- RLS: cualquier cuenta autenticada (todo el staff) lee el
-- calendario; solo Dirección General lo carga y edita.
-- ═══════════════════════════════════════════════════════════════
alter table public.eventos_calendario enable row level security;

create policy eventos_calendario_select_authenticated on public.eventos_calendario
  for select to authenticated using (true);

create policy eventos_calendario_write_director on public.eventos_calendario
  for all to authenticated
  using (
    exists (select 1 from public.directores d where d.email = (auth.jwt() ->> 'email'))
  )
  with check (
    exists (select 1 from public.directores d where d.email = (auth.jwt() ->> 'email'))
  );
