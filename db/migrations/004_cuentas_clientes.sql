-- ============================================================================
-- 004_cuentas_clientes.sql
--
-- Suma cuentas de cliente OPCIONALES (el cliente elige "continuar con
-- cuenta" o "reservar sin cuenta" — el flujo sin cuenta sigue funcionando
-- exactamente igual que hoy, no se toca).
--
-- Es 100% aditiva: no modifica ni borra ninguna tabla existente. La única
-- adición sobre una tabla existente es una columna nueva NULLABLE en
-- `turnos` (cliente_id) — las reservas ya existentes quedan con ese campo
-- vacío, sin ningún efecto sobre ellas.
-- ============================================================================

-- Perfiles: une cada usuario de Supabase Auth (auth.users) con un rol.
-- El login del panel admin ahora exige rol = 'barbero'; cualquier otra
-- cuenta que se registre en el sitio público es 'cliente' por defecto.
create table if not exists perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text,
  telefono text,
  rol text not null default 'cliente' check (rol in ('cliente', 'barbero')),
  created_at timestamptz default now()
);

-- Crea el perfil automáticamente apenas alguien se registra (rol 'cliente'
-- por defecto — el rol 'barbero' se asigna a mano, ver instrucciones abajo).
create or replace function crear_perfil_automatico()
returns trigger as $$
begin
  insert into perfiles (id, nombre, telefono, rol)
  values (new.id, new.raw_user_meta_data->>'nombre', new.raw_user_meta_data->>'telefono', 'cliente');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function crear_perfil_automatico();

-- Vincula (opcionalmente) una reserva con la cuenta de cliente que la hizo.
-- NULL = reserva de invitado (sin cuenta), como todas las que ya existen.
alter table turnos add column if not exists cliente_id uuid references perfiles(id);
create index if not exists idx_turnos_cliente on turnos(cliente_id);

alter table perfiles enable row level security;

create policy "cada uno lee y edita su propio perfil" on perfiles
  for select using (auth.uid() = id);
create policy "cada uno edita su propio perfil" on perfiles
  for update using (auth.uid() = id);
create policy "el barbero lee todos los perfiles" on perfiles
  for select using (
    exists (select 1 from perfiles p where p.id = auth.uid() and p.rol = 'barbero')
  );

-- ============================================================================
-- IMPORTANTE — paso manual único, después de correr esta migración:
-- Tu cuenta de barbero (la que ya usás para entrar al panel admin) se creó
-- ANTES de que existiera esta tabla, así que el trigger de arriba no la
-- alcanzó. Corré esto una sola vez, reemplazando el email por el tuyo:
--
--   insert into perfiles (id, nombre, rol)
--   select id, 'Barbero', 'barbero' from auth.users where email = 'TU_EMAIL_DE_ADMIN_ACA'
--   on conflict (id) do update set rol = 'barbero';
-- ============================================================================
