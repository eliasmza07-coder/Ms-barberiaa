-- Arregla el error 400 al agregar/editar/borrar servicios desde el panel.
-- Causa: la tabla `servicios` tiene una columna `orden` que el código
-- nunca envía; si es NOT NULL sin valor por defecto, cualquier guardado
-- falla. Esto le pone un default de 0 y completa las filas que ya
-- tuvieran ese campo vacío.
do $$
begin
  if exists (select 1 from information_schema.columns where table_name = 'servicios' and column_name = 'orden') then
    alter table servicios alter column orden set default 0;
    update servicios set orden = 0 where orden is null;
  end if;
end $$;

alter table servicios add column if not exists "desc" text;
