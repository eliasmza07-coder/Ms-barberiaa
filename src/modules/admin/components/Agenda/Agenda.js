/**
 * modules/admin/components/Agenda/Agenda.js
 * Componente de UI: pinta la grilla horaria del admin y el popover de un
 * slot. Migrado desde el render de cargarAgendaAdmin() y abrirPopoverSlot()
 * del index.html original.
 */
import { refreshIcons } from '../../../../shared/utils/dom.utils.js';

export function renderGrillaAdmin(container, filas, onSlotClick) {
  container.innerHTML = filas
    .map(({ hora, estado, turno }, i) => {
      const colorDot = estado === 'libre' ? 'bg-libre' : estado === 'reservado' ? 'bg-reservado' : 'bg-bloqueado';
      const label =
        estado === 'reservado'
          ? `<span class="text-bone font-medium">${turno.cliente_nombre}</span> <span class="text-bone-dim text-xs">— ${turno.servicio_nombre} (${turno.estado})</span>`
          : estado === 'bloqueado'
          ? `<span class="text-bone-dim italic">Bloqueado</span>`
          : `<span class="text-bone-dim text-xs">Disponible</span>`;

      return `<div class="flex items-center justify-between px-5 py-3.5 hover:bg-ink-surface transition-colors cursor-pointer opacity-0 animate-fade-in" style="animation-delay:${Math.min(i * 12, 250)}ms" data-hora="${hora}" data-estado="${estado}" data-turno-id="${turno ? turno.id : ''}">
        <div class="flex items-center gap-3.5">
          <span class="font-mono text-xs text-gold w-12">${hora}</span>
          <span class="w-2 h-2 rounded-full ${colorDot}"></span>
          <span class="text-xs sm:text-sm">${label}</span>
        </div>
        <i data-lucide="chevron-right" class="w-3.5 h-3.5 text-bone-dim"></i>
      </div>`;
    })
    .join('');

  refreshIcons();

  container.querySelectorAll('[data-hora]').forEach((row) => {
    row.addEventListener('click', (evt) => {
      const { hora, estado, turnoId } = row.dataset;
      onSlotClick(evt, hora, estado, turnoId || null);
    });
  });
}

export function renderPopover(popoverEl, contenidoEl, { hora, fecha, estado, turno, callbacks }) {
  let html = `<p class="font-mono text-gold text-xs mb-2">${hora} — ${fecha}</p>`;

  if (estado === 'reservado' && turno) {
    html += `<p class="text-bone text-xs font-semibold mb-1">${turno.cliente_nombre}</p>
             <p class="text-bone-dim text-[10px] mb-3 font-mono">Tel: ${turno.cliente_telefono}</p>
             <div class="space-y-1.5">
               ${turno.estado === 'pendiente' ? `<button data-action="confirmar" class="w-full bg-libre text-ink py-2 text-[10px] uppercase tracking-widest font-semibold transition-colors">Confirmar</button>` : ''}
               <button data-action="cancelar" class="w-full border border-bloqueado text-bloqueado hover:bg-bloqueado hover:text-ink py-2 text-[10px] uppercase tracking-widest font-mono transition-colors">Cancelar Turno</button>
             </div>`;
  } else {
    html += `<button data-action="bloquear-hora" class="w-full border border-bloqueado text-bloqueado hover:bg-bloqueado hover:text-ink py-2 text-[10px] uppercase tracking-widest font-mono transition-colors">Bloquear Hora</button>`;
  }

  contenidoEl.innerHTML = html;
  contenidoEl.querySelector('[data-action="confirmar"]')?.addEventListener('click', callbacks.onConfirmar);
  contenidoEl.querySelector('[data-action="cancelar"]')?.addEventListener('click', callbacks.onCancelar);
  contenidoEl.querySelector('[data-action="bloquear-hora"]')?.addEventListener('click', callbacks.onBloquearHora);
}

export function posicionarPopover(popoverEl, rectOrigen) {
  popoverEl.style.top = `${Math.min(rectOrigen.bottom + window.scrollY + 4, window.innerHeight - 200)}px`;
  popoverEl.style.left = `${Math.min(rectOrigen.left, window.innerWidth - 270)}px`;
  popoverEl.classList.remove('hidden');
}

export function actualizarBotonDia(btnEl, textoEl, diaBloqueado) {
  if (diaBloqueado) {
    textoEl.textContent = 'Desbloquear día';
    btnEl.className = 'border border-libre text-libre hover:bg-libre hover:text-ink px-4 py-2.5 text-[10px] uppercase tracking-widest font-mono transition-colors flex items-center gap-1.5';
  } else {
    textoEl.textContent = 'Bloquear día';
    btnEl.className = 'border border-bloqueado text-bloqueado hover:bg-bloqueado hover:text-ink px-4 py-2.5 text-[10px] uppercase tracking-widest font-mono transition-colors flex items-center gap-1.5';
  }
}
