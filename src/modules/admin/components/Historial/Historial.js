/**
 * modules/admin/components/Historial/Historial.js
 * Componente de UI: pinta la tabla de historial de turnos.
 * Migrado desde cargarHistorialGeneral() del index.html original.
 */
export function renderHistorial(tbodyEl, turnos, { onBorrar }) {
  if (!turnos || turnos.length === 0) {
    tbodyEl.innerHTML = `<tr><td colspan="7" class="p-4 text-center font-mono text-bone-dim">No hay turnos.</td></tr>`;
    return;
  }

  tbodyEl.innerHTML = turnos
    .map((t, i) => {
      const colorEstado =
        t.estado === 'confirmado' ? 'text-reservado' : t.estado === 'pendiente' ? 'text-pendiente' : 'text-bloqueado';
      return `<tr class="hover:bg-ink-surface/50 transition-colors opacity-0 animate-fade-in" style="animation-delay:${Math.min(i * 25, 300)}ms" data-id="${t.id}">
        <td class="p-3.5">${t.fecha}</td>
        <td class="p-3.5 text-gold">${t.hora.slice(0, 5)}</td>
        <td class="p-3.5 text-bone">${t.cliente_nombre}</td>
        <td class="p-3.5">${t.cliente_telefono}</td>
        <td class="p-3.5">${t.servicio_nombre}</td>
        <td class="p-3.5 uppercase font-semibold ${colorEstado}">${t.estado}</td>
        <td class="p-3.5 text-right">
          <button data-action="borrar" class="text-bloqueado hover:underline text-[10px] uppercase tracking-wider">Borrar</button>
        </td>
      </tr>`;
    })
    .join('');

  tbodyEl.querySelectorAll('[data-id]').forEach((row) => {
    row.querySelector('[data-action="borrar"]').addEventListener('click', () => onBorrar(row.dataset.id));
  });
}

export function mostrarCargandoHistorial(tbodyEl) {
  tbodyEl.innerHTML = Array.from({ length: 5 })
    .map(
      (_, i) => `<tr class="animate-pulse" style="animation-delay:${i * 60}ms">
        ${Array.from({ length: 7 }).map(() => `<td class="p-3.5"><div class="h-3 bg-ink-line rounded w-4/5"></div></td>`).join('')}
      </tr>`
    )
    .join('');
}

export function mostrarErrorHistorial(tbodyEl) {
  tbodyEl.innerHTML = `<tr><td colspan="7" class="p-4 text-center font-mono text-bloqueado">Error al cargar.</td></tr>`;
}
