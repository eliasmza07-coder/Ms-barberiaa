/**
 * modules/landing/components/Experiencia/Experiencia.js
 * Pinta las tarjetas de la sección "Experiencia", ahora leídas desde
 * la tabla `experiencia_items` en vez de estar fijas en el HTML.
 */
import { refreshIcons } from '../../../../shared/utils/dom.utils.js';

export function renderExperiencia(container, items) {
  container.innerHTML = items
    .map(
      (item) => `
    <div class="card-edge bg-ink-surface p-6">
      <i data-lucide="${item.icono || 'star'}" class="w-6 h-6 text-gold mb-3"></i>
      <h4 class="font-display text-xl text-bone mb-1">${item.titulo}</h4>
      <p class="text-bone-dim text-xs font-light leading-relaxed">${item.descripcion || ''}</p>
    </div>
  `
    )
    .join('');
  refreshIcons();
}
