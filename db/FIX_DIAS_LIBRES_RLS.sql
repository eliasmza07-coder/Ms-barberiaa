-- Asegura que el barbero (autenticado) pueda leer, crear y borrar
-- bloqueos de día/hora sin restricciones, y que el público pueda seguir
-- leyéndolos (para saber qué días no están disponibles). Si en algún
-- momento se activó RLS en estas tablas sin políticas (desde el panel de
-- Supabase, por ejemplo), esto lo corrige sin tocar ningún dato.
alter table dias_libres enable row level security;
alter table horas_bloqueadas enable row level security;
alter table config_jornada enable row level security;

drop policy if exists "lectura publica dias_libres" on dias_libres;
create policy "lectura publica dias_libres" on dias_libres for select using (true);
drop policy if exists "escritura autenticados dias_libres" on dias_libres;
create policy "escritura autenticados dias_libres" on dias_libres for all using (auth.role() = 'authenticated');
drop policy if exists "insercion publica dias_libres" on dias_libres;
create policy "insercion publica dias_libres" on dias_libres for insert with check (true);

drop policy if exists "lectura publica horas_bloqueadas" on horas_bloqueadas;
create policy "lectura publica horas_bloqueadas" on horas_bloqueadas for select using (true);
drop policy if exists "escritura autenticados horas_bloqueadas" on horas_bloqueadas;
create policy "escritura autenticados horas_bloqueadas" on horas_bloqueadas for all using (auth.role() = 'authenticated');

drop policy if exists "lectura publica config_jornada" on config_jornada;
create policy "lectura publica config_jornada" on config_jornada for select using (true);
drop policy if exists "escritura autenticados config_jornada" on config_jornada;
create policy "escritura autenticados config_jornada" on config_jornada for all using (auth.role() = 'authenticated');
