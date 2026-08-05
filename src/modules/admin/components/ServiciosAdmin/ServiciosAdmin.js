/**
 * modules/admin/components/ServiciosAdmin/ServiciosAdmin.js
 * Componente de UI: pinta las tarjetas de servicios en el admin.
 * Migrado desde renderServiciosAdmin() del index.html original.
 */
import { formatoGs } from '../../../../shared/utils/currency.utils.js';
import { refreshIcons } from '../../../../shared/utils/dom.utils.js';

export function renderServiciosAdmin(container, servicios, { onEditar, onEliminar }) {
  container.innerHTML = servicios
    .map(
      (s, i) => `
    <div class="card-edge bg-ink p-5 flex flex-col justify-between opacity-0 animate-fade-in-up" style="animation-delay:${Math.min(i * 40, 300)}ms" data-id="${s.id}">
      <div>
        <div class="flex items-center justify-between mb-2.5">
          <span class="text-[10px] font-mono uppercase tracking-widest text-gold">${s.duracion} MIN</span>
          <span class="font-mono text-gold text-xs font-medium">${formatoGs(s.precio)}</span>
        </div>
        <h4 class="font-display text-lg text-bone mb-1">${s.nombre}</h4>
        <p class="text-bone-dim text-[11px] mb-4">${s.desc || ''}</p>
      </div>
      <div class="flex items-center gap-2 pt-3 border-t border-ink-line">
        <button data-action="editar" class="flex-1 border border-ink-line hover:border-gold text-bone py-2 text-[10px] uppercase tracking-widest font-mono transition-colors">Editar</button>
        <button data-action="eliminar" class="border border-bloqueado/40 text-bloqueado hover:bg-bloqueado hover:text-ink px-3 py-2 text-xs transition-colors"><i data-lucide="trash-2" class="w-3.5 h-3.5"></i></button>
      </div>
    </div>
  `
    )
    .join('');

  refreshIcons();

  container.querySelectorAll('[data-id]').forEach((card) => {
    const id = card.dataset.id;
    card.querySelector('[data-action="editar"]').addEventListener('click', () => onEditar(id));
    card.querySelector('[data-action="eliminar"]').addEventListener('click', () => onEliminar(id));
  });
}
