/**
 * modules/landing/components/Testimonios/Testimonios.js
 * Pinta las reseñas aprobadas (estrellas + comentario) en la landing.
 * Si no hay ninguna aprobada todavía, oculta la sección.
 */
export function renderTestimonios(sectionEl, container, items) {
  if (!items || items.length === 0) {
    sectionEl.classList.add('hidden');
    return;
  }
  sectionEl.classList.remove('hidden');
  container.innerHTML = items
    .map((r) => {
      const estrellas = '★'.repeat(r.calificacion) + '☆'.repeat(5 - r.calificacion);
      return `
    <div class="card-edge bg-ink-surface p-6">
      <p class="text-gold text-sm tracking-widest mb-3">${estrellas}</p>
      <p class="text-bone-dim text-sm font-light leading-relaxed mb-4">"${r.comentario}"</p>
      <p class="text-bone text-xs uppercase tracking-widest font-mono">— ${r.cliente_nombre}</p>
    </div>`;
    })
    .join('');
}

export function mostrarMensajeResena(elId, texto, tipo) {
  const el = document.getElementById(elId);
  if (!el) return;
  el.textContent = texto;
  const color = tipo === 'error' ? 'text-bloqueado' : 'text-libre';
  el.className = `text-xs mt-3 text-center font-mono ${color}`;
}
