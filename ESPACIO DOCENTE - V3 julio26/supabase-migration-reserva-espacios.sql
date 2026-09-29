-- ═══════════════════════════════════════════════════════════════
-- Reserva de espacios · Austin Eco Bilingual School
-- Grilla de disponibilidad de salones especiales (Biblioteca, Art
-- Room, Design Lab, Arena). A diferencia del calendario institucional
-- (que carga Dirección General), estas reservas las carga cada
-- docente desde su propio Espacio Docente; todo el staff ve la
-- disponibilidad, pero cada uno solo cancela sus propias reservas.
-- ═══════════════════════════════════════════════════════════════

create table if not exists public.reservas_espacios (
  id uuid primary key default gen_random_uuid(),
  salon text not null
    check (salon in ('Biblioteca','Art Room','Design Lab','Arena')),
  fecha date not null,
  hora_inicio time not null,
  motivo text,
  user_id uuid not null references auth.users(id) on delete cascade,
  docente_email text not null,
  docente_nombre text,
  created_at timestamptz not null default now(),
  unique (salon, fecha, hora_inicio)
);

create index if not exists reservas_espacios_fecha_idx on public.reservas_espacios (fecha);

-- ═══════════════════════════════════════════════════════════════
-- RLS: cualquier cuenta autenticada ve todas las reservas (para
-- que todo el staff conozca la disponibilidad real); cada docente
-- solo puede crear reservas a su propio nombre y cancelar las suyas.
-- ═══════════════════════════════════════════════════════════════
alter table public.reservas_espacios enable row level security;

create policy reservas_espacios_select_authenticated on public.reservas_espacios
  for select to authenticated using (true);

create policy reservas_espacios_insert_own on public.reservas_espacios
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and docente_email = (auth.jwt() ->> 'email')
  );

create policy reservas_espacios_delete_own on public.reservas_espacios
  for delete to authenticated
  using (user_id = auth.uid());
