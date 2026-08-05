-- ============================================================================
-- 003_resenas_y_fixes.sql
--
-- Dos cosas en este archivo:
--   A) Fix de datos: limpia duplicados en `dias_libres` (causa del bug de
--      "bloquear/desbloquear día" que a veces se desincronizaba) y agrega
--      una restricción para que no vuelva a pasar.
--   B) Tabla nueva `resenas` (reseñas de clientes) para la sección pública
--      de testimonios, moderable desde el panel admin.
--
-- Es seguro correr esto sobre la base actual en producción.
-- ============================================================================

-- A) -------------------------------------------------------------------------
-- Si en algún momento quedaron dos filas con la misma fecha en dias_libres
-- (por el bug), esto se queda con la más vieja y borra el resto.
delete from dias_libres a
using dias_libres b
where a.fecha = b.fecha
  and a.id > b.id;

-- Evita que el bug pueda volver a ocurrir a nivel de base de datos.
alter table dias_libres
  add constraint dias_libres_fecha_unique unique (fecha);

-- B) -------------------------------------------------------------------------
create table if not exists resenas (
  id bigint generated always as identity primary key,
  cliente_nombre text not null,
  calificacion int not null check (calificacion between 1 and 5),
  comentario text not null,
  aprobada boolean not null default false,  -- el barbero aprueba antes de que se muestre en público
  orden int not null default 0,
  created_at timestamptz default now()
);

alter table resenas enable row level security;

-- El público puede INSERTAR su reseña (queda pendiente de aprobación) y
-- LEER solo las aprobadas. El barbero (autenticado) puede leer/editar/borrar todo.
create policy "lectura publica resenas aprobadas" on resenas
  for select using (aprobada = true);

create policy "insercion publica de resenas" on resenas
  for insert with check (aprobada = false);

create policy "lectura completa autenticados resenas" on resenas
  for select using (auth.role() = 'authenticated');

create policy "escritura autenticados resenas" on resenas
  for update using (auth.role() = 'authenticated');

create policy "borrado autenticados resenas" on resenas
  for delete using (auth.role() = 'authenticated');
