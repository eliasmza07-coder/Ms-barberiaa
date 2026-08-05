/**
 * shared/utils/theme.utils.js
 * Aplica la paleta de colores del sitio en tiempo real, sin recargar ni
 * recompilar nada. Como tailwind.config (en index.html) define los
 * colores como rgb(var(--color-x-rgb) / <alpha-value>), alcanza con
 * cambiar esas variables CSS en :root para que TODA la web (clases
 * bg-gold, text-bone, border-ink-line, etc.) se actualice sola.
 */

/** Convierte "#RRGGBB" a "R G B" (formato que usan las variables CSS acá). */
export function hexARgbTriplete(hex) {
  const limpio = hex.replace('#', '');
  const r = parseInt(limpio.substring(0, 2), 16);
  const g = parseInt(limpio.substring(2, 4), 16);
  const b = parseInt(limpio.substring(4, 6), 16);
  return `${r} ${g} ${b}`;
}

/** Convierte "R G B" de vuelta a "#RRGGBB" (para precargar los <input type="color">). */
export function rgbTripleteAHex(triplete) {
  if (!triplete) return '#000000';
  const [r, g, b] = triplete.trim().split(/\s+/).map(Number);
  const aHex = (n) => n.toString(16).padStart(2, '0');
  return `#${aHex(r)}${aHex(g)}${aHex(b)}`;
}

/**
 * Aplica los 4 colores personalizables. Las demás variables (ink-line,
 * ink-soft, bone-dim, gold-bright/dim) se derivan automáticamente a partir
 * de estos 4, mezclándolas con negro/blanco — así con solo 4 selectores
 * de color todo el sitio se mantiene coherente.
 */
export function aplicarTema({ color_fondo, color_superficie, color_texto, color_acento }) {
  const root = document.documentElement.style;

  if (color_fondo) {
    root.setProperty('--color-ink-rgb', hexARgbTriplete(color_fondo));
  }
  if (color_superficie) {
    root.setProperty('--color-ink-surface-rgb', hexARgbTriplete(color_superficie));
  }
  if (color_texto) {
    root.setProperty('--color-bone-rgb', hexARgbTriplete(color_texto));
  }
  if (color_acento) {
    const rgb = hexARgbTriplete(color_acento);
    root.setProperty('--color-gold-rgb', rgb);
    root.setProperty('--color-gold-bright-rgb', rgb);
  }
}

export const TEMA_DEFAULT = {
  color_fondo: '#0A0A0A',
  color_superficie: '#1A1A1A',
  color_texto: '#F5F5F4',
  color_acento: '#E8E8E6',
};
