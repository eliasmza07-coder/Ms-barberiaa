/**
 * modules/reservations/components/ReservationForm/ReservationForm.js
 *
 * Componente de UI del formulario de reservas. Pinta el catálogo, el grid
 * de horarios (con animación escalonada), el indicador de progreso del
 * wizard, y la tarjeta de seguimiento post-envío. No decide reglas de
 * negocio ni llama a Supabase — solo recibe datos ya calculados y los
 * renderiza; el estado y las decisiones viven en reservations.controller.js.
 */
import { formatoGs } from '../../../../shared/utils/currency.utils.js';
import { refreshIcons, qs } from '../../../../shared/utils/dom.utils.js';

export function renderListaServicios(container, servicios) {
  container.innerHTML = servicios
    .map(
      (s) => `
    <div class="card-edge bg-ink p-6 flex flex-col justify-between hover:border-gold transition-colors group">
      <div>
        <div class="flex items-center justify-between mb-3">
          <span class="text-[10px] font-mono uppercase tracking-widest text-gold px-2 py-0.5 bg-gold/10 border border-gold/20">${s.duracion} MIN</span>
          <i data-lucide="scissors" class="w-4 h-4 text-bone-dim group-hover:text-gold transition-colors"></i>
        </div>
        <h3 class="font-display text-xl text-bone mb-1">${s.nombre}</h3>
        <p class="text-bone-dim text-xs leading-relaxed mb-4 font-light">${s.desc || ''}</p>
      </div>
      <div class="pt-3 border-t border-ink-line flex items-center justify-between">
        <span class="text-[10px] uppercase tracking-widest text-bone-dim font-mono">Precio</span>
        <span class="font-mono text-gold font-medium">${formatoGs(s.precio)}</span>
      </div>
    </div>
  `
    )
    .join('');
  refreshIcons();
}

export function poblarSelectServicios(selectEl, servicios) {
  selectEl.innerHTML = servicios
    .map((s) => `<option value="${s.id}" data-duracion="${s.duracion}">${s.nombre} — ${formatoGs(s.precio)} (${s.duracion} min)</option>`)
    .join('');
}

/** Tarjetas de servicio clickeables del paso 1 — más dinámico que un <select>. */
export function renderTarjetasServicio(container, servicios, idSeleccionado, onSeleccionar) {
  container.innerHTML = servicios
    .map((s, i) => {
      const activo = String(s.id) === String(idSeleccionado);
      const clasesActivo = activo
        ? 'border-gold bg-gold/10 shadow-lg shadow-gold/10'
        : 'border-ink-line bg-ink hover:border-gold/50';
      return `<button type="button" data-servicio-id="${s.id}" style="animation-delay:${Math.min(i * 50, 250)}ms" class="tarjeta-servicio opacity-0 animate-fade-in-up border ${clasesActivo} rounded-xl p-4 flex items-center justify-between gap-3 text-left transition-all duration-250">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-full ${activo ? 'bg-gold text-ink' : 'bg-ink-surface text-gold'} flex items-center justify-center shrink-0 transition-colors duration-250">
            <i data-lucide="scissors" class="w-4 h-4"></i>
          </div>
          <div>
            <p class="text-bone text-sm font-medium">${s.nombre}</p>
            <p class="text-bone-dim text-[11px] font-mono">${s.duracion} min</p>
          </div>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <span class="font-mono text-gold text-sm">${formatoGs(s.precio)}</span>
          <i data-lucide="check-circle-2" class="w-4 h-4 ${activo ? 'text-gold opacity-100' : 'opacity-0'} transition-opacity duration-250"></i>
        </div>
      </button>`;
    })
    .join('');
  refreshIcons();

  container.querySelectorAll('[data-servicio-id]').forEach((btn) => {
    btn.addEventListener('click', () => onSeleccionar(btn.dataset.servicioId));
  });
}

/** Grid de horarios con animación escalonada (cada botón aparece con un pequeño delay). */
export function renderGridHorarios(gridEl, bloques) {
  if (!bloques || bloques.length === 0) {
    gridEl.innerHTML = `<p class="col-span-full text-bone-dim text-xs text-center py-4 font-mono">No hay horarios para este día.</p>`;
    return;
  }
  gridEl.innerHTML = bloques
    .map(({ hora, estado }, i) => {
      const disabled = estado !== 'libre';
      let clases = 'border-libre/40 text-bone hover:bg-libre hover:text-ink cursor-pointer bg-ink-surface';
      if (disabled) clases = 'border-bloqueado/20 text-bone-dim/40 cursor-not-allowed opacity-40 bg-ink';
      const delay = Math.min(i * 18, 400);
      return `<button type="button" ${disabled ? 'disabled' : ''} data-hora="${hora}" style="animation-delay:${delay}ms" class="slot-btn opacity-0 animate-fade-in-up border ${clases} rounded-lg font-mono text-xs py-2.5 transition-all duration-200">${hora}</button>`;
    })
    .join('');
}

/** Marca visualmente la hora elegida con un pequeño "pop" (scale) además del color. */
export function marcarHoraSeleccionada(gridEl, btnEl) {
  gridEl.querySelectorAll('.slot-btn').forEach((b) => {
    if (!b.disabled) b.classList.remove('bg-gold', 'text-ink', 'border-gold', 'font-semibold', 'scale-110');
  });
  btnEl.classList.add('bg-gold', 'text-ink', 'border-gold', 'font-semibold', 'scale-110');
  setTimeout(() => btnEl.classList.remove('scale-110'), 180);
}

export function mostrarCargando(gridEl) {
  gridEl.innerHTML = `<div class="col-span-full flex items-center justify-center gap-2 py-4">
    <span class="w-1.5 h-1.5 rounded-full bg-gold animate-pulse-slow"></span>
    <span class="w-1.5 h-1.5 rounded-full bg-gold animate-pulse-slow" style="animation-delay:150ms"></span>
    <span class="w-1.5 h-1.5 rounded-full bg-gold animate-pulse-slow" style="animation-delay:300ms"></span>
    <span class="text-bone-dim text-xs font-mono ml-2">Calculando disponibilidad...</span>
  </div>`;
}

export function mostrarFechaPasada(gridEl) {
  gridEl.innerHTML = `<p class="col-span-full text-bloqueado text-xs text-center py-3 font-mono">No se puede reservar en fechas pasadas.</p>`;
}

export function mostrarErrorHorarios(gridEl) {
  gridEl.innerHTML = `<p class="col-span-full text-bloqueado text-xs text-center font-mono">Error al cargar horarios.</p>`;
}

// ---------- Indicador de progreso (wizard de 4 pasos) ----------
const PASOS = [1, 2, 3, 4];
const PANELES = {
  1: 'pasoPanelServicio',
  2: 'pasoPanelFecha',
  3: 'pasoPanelHora',
  4: 'pasoPanelDatos',
};

/**
 * @param {number} pasoActual - el paso que se está mostrando ahora mismo.
 * @param {number[]} completados - pasos que ya tienen dato cargado (pueden
 *   ser más que pasoActual si el cliente completó pasos y volvió atrás).
 * @param {Function} onClickPaso - callback(n) cuando se clickea un paso ya completado, para saltar directo ahí.
 */
export function renderProgreso(pasoActual, completados, onClickPaso) {
  PASOS.forEach((n) => {
    const wrap = document.querySelector(`[data-paso-indicador="${n}"]`);
    if (!wrap) return;
    const circulo = wrap.children[0];
    const label = wrap.children[1];
    const hecho = completados.includes(n) && n !== pasoActual;
    const esActual = n === pasoActual;

    if (esActual) {
      circulo.className = 'w-7 h-7 rounded-full border flex items-center justify-center text-[11px] font-mono transition-all duration-300 border-gold text-gold scale-110';
      circulo.textContent = n;
      label.className = 'hidden sm:inline text-[10px] uppercase tracking-widest font-mono transition-colors duration-300 text-bone';
    } else if (hecho) {
      circulo.className = 'w-7 h-7 rounded-full border flex items-center justify-center text-[11px] font-mono transition-all duration-300 bg-gold border-gold text-ink';
      circulo.innerHTML = '✓';
      label.className = 'hidden sm:inline text-[10px] uppercase tracking-widest font-mono transition-colors duration-300 text-gold';
    } else {
      circulo.className = 'w-7 h-7 rounded-full border flex items-center justify-center text-[11px] font-mono transition-all duration-300 border-ink-line text-bone-dim';
      circulo.textContent = n;
      label.className = 'hidden sm:inline text-[10px] uppercase tracking-widest font-mono transition-colors duration-300 text-bone-dim';
    }

    wrap.disabled = !hecho;
    wrap.style.cursor = hecho ? 'pointer' : 'default';
    wrap.onclick = hecho ? () => onClickPaso(n) : null;
  });
}

/** Muestra solo el panel del paso indicado (1-4) y oculta los demás. */
export function mostrarPasoPanel(n) {
  Object.entries(PANELES).forEach(([num, id]) => {
    qs(id).classList.toggle('hidden', Number(num) !== n);
  });
}

/** Ajusta los botones de navegación (Atrás visible salvo en el paso 1; Siguiente vs Confirmar). */
export function actualizarNavegacion(pasoActual, totalPasos) {
  const btnAtras = qs('btnPasoAtras');
  const btnSiguiente = qs('btnPasoSiguiente');
  const btnConfirmar = qs('btnConfirmar');

  btnAtras.classList.toggle('hidden', pasoActual === 1);
  if (pasoActual === 1) btnAtras.classList.remove('flex'); else btnAtras.classList.add('flex');

  const esUltimoPaso = pasoActual === totalPasos;
  btnSiguiente.classList.toggle('hidden', esUltimoPaso);
  btnConfirmar.classList.toggle('hidden', !esUltimoPaso);
  if (esUltimoPaso) btnConfirmar.classList.add('flex'); else btnConfirmar.classList.remove('flex');
}

// ---------- Tarjeta de seguimiento ----------
export function mostrarFormulario() {
  qs('wizardReserva').classList.remove('hidden');
  qs('cardSeguimiento').classList.add('hidden');
}

export function mostrarSeguimiento({ servicio_nombre, fecha, hora, precio }) {
  qs('wizardReserva').classList.add('hidden');
  qs('cardSeguimiento').classList.remove('hidden');
  qs('seguimientoServicio').textContent = servicio_nombre;
  qs('seguimientoFecha').textContent = fecha;
  qs('seguimientoHora').textContent = hora;
  qs('seguimientoPrecio').textContent = formatoGs(precio);
  actualizarEstadoSeguimiento('pendiente');
}

export function actualizarEstadoSeguimiento(estado) {
  const icono = qs('seguimientoIcono');
  const iconoWrap = qs('seguimientoIconoWrap');
  const texto = qs('seguimientoEstadoTexto');

  if (estado === 'confirmado') {
    iconoWrap.className = 'w-16 h-16 rounded-full border-2 border-libre flex items-center justify-center mx-auto mb-5 transition-colors duration-500 animate-scale-in';
    icono.setAttribute('data-lucide', 'check-circle-2');
    icono.setAttribute('class', 'w-7 h-7 text-libre transition-colors duration-500');
    texto.textContent = '¡Turno confirmado!';
    texto.className = 'text-libre uppercase tracking-[0.25em] text-xs font-mono mb-2 transition-colors duration-500';
  } else if (estado === 'cancelado') {
    iconoWrap.className = 'w-16 h-16 rounded-full border-2 border-bloqueado flex items-center justify-center mx-auto mb-5 transition-colors duration-500';
    icono.setAttribute('data-lucide', 'x-circle');
    icono.setAttribute('class', 'w-7 h-7 text-bloqueado transition-colors duration-500');
    texto.textContent = 'Turno cancelado';
    texto.className = 'text-bloqueado uppercase tracking-[0.25em] text-xs font-mono mb-2 transition-colors duration-500';
  } else {
    iconoWrap.className = 'w-16 h-16 rounded-full border-2 border-pendiente flex items-center justify-center mx-auto mb-5 transition-colors duration-500';
    icono.setAttribute('data-lucide', 'clock');
    icono.setAttribute('class', 'w-7 h-7 text-pendiente transition-colors duration-500');
    texto.textContent = 'Pendiente de confirmación';
    texto.className = 'text-pendiente uppercase tracking-[0.25em] text-xs font-mono mb-2 transition-colors duration-500';
  }
  refreshIcons();
}

// ---------- Aviso flotante (visible fuera del modal) ----------
const ESTILOS_ESTADO = {
  confirmado: { borde: 'border-libre', texto: 'text-libre', icono: 'check-circle-2', label: 'Confirmado' },
  cancelado: { borde: 'border-bloqueado', texto: 'text-bloqueado', icono: 'x-circle', label: 'Cancelado' },
  pendiente: { borde: 'border-pendiente', texto: 'text-pendiente', icono: 'clock', label: 'Pendiente' },
};

export function mostrarBadgeSeguimiento(estado) {
  const e = ESTILOS_ESTADO[estado] || ESTILOS_ESTADO.pendiente;
  qs('badgeSeguimiento').classList.remove('hidden');
  qs('badgeIconoWrap').className = `w-8 h-8 rounded-full border-2 ${e.borde} flex items-center justify-center shrink-0 transition-colors duration-500`;
  const icono = qs('badgeIcono');
  icono.setAttribute('data-lucide', e.icono);
  icono.setAttribute('class', `w-4 h-4 ${e.texto} transition-colors duration-500`);
  const textoEl = qs('badgeEstadoTexto');
  textoEl.textContent = e.label;
  textoEl.className = `${e.texto} text-[10px] uppercase tracking-widest font-mono transition-colors duration-500`;
  refreshIcons();
}

export function ocultarBadgeSeguimiento() {
  qs('badgeSeguimiento').classList.add('hidden');
}
