/**
 * modules/landing/components/Footer/Footer.js
 * Pinta los enlaces a redes sociales, tanto en el footer como en la
 * sección de ubicación. Migra el ícono correcto de Lucide por plataforma.
 */
import { refreshIcons } from '../../../../shared/utils/dom.utils.js';

const ICONOS = {
  whatsapp: 'message-circle',
  instagram: 'instagram',
  facebook: 'facebook',
  tiktok: 'music-2',
  maps: 'map-pin',
};

export function renderRedesSociales(container, redes) {
  if (!container) return;
  container.innerHTML = redes
    .map(
      (r) => `
    <a href="${r.url}" target="_blank" rel="noopener" class="text-bone-dim hover:text-gold transition-colors" aria-label="${r.plataforma}">
      <i data-lucide="${ICONOS[r.plataforma] || 'link'}" class="w-4 h-4"></i>
    </a>
  `
    )
    .join('');
  refreshIcons();
}
