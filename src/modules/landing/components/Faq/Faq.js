/**
 * modules/landing/components/Faq/Faq.js
 * Pinta el acordeón de preguntas frecuentes. Si no hay preguntas
 * cargadas, oculta la sección.
 */
export function renderFaq(sectionEl, container, items) {
  if (!items || items.length === 0) {
    sectionEl.classList.add('hidden');
    return;
  }
  sectionEl.classList.remove('hidden');
  container.innerHTML = items
    .map(
      (f, i) => `
    <details class="card-edge bg-ink-surface px-5 py-4 group" ${i === 0 ? 'open' : ''}>
      <summary class="cursor-pointer text-bone font-medium text-sm flex items-center justify-between list-none">
        ${f.pregunta}
        <i data-lucide="chevron-down" class="w-4 h-4 text-gold shrink-0 transition-transform group-open:rotate-180"></i>
      </summary>
      <p class="text-bone-dim text-xs font-light leading-relaxed mt-3">${f.respuesta}</p>
    </details>
  `
    )
    .join('');
}
