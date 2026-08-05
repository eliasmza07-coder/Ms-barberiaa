/**
 * modules/landing/components/Galeria/Galeria.js
 * Pinta la grilla de fotos de la sección "Galería". Si no hay fotos
 * cargadas todavía, oculta la sección en vez de mostrar un hueco vacío.
 */
export function renderGaleria(sectionEl, container, items) {
  if (!items || items.length === 0) {
    sectionEl.classList.add('hidden');
    return;
  }
  sectionEl.classList.remove('hidden');
  container.innerHTML = items
    .map(
      (g) => `
    <div class="card-edge overflow-hidden aspect-square bg-ink-surface">
      <img src="${g.imagen_url}" alt="${g.descripcion || ''}" class="w-full h-full object-cover hover:scale-105 transition-transform duration-500" loading="lazy">
    </div>
  `
    )
    .join('');
}
