/**
 * modules/admin/components/ContenidoAdmin/ContenidoAdmin.js
 *
 * Componente de UI genérico para las 4 listas editables del tab
 * "Contenido" (Redes, Experiencia, Galería, FAQ). En vez de repetir el
 * mismo render/lectura de formulario 4 veces, se parametriza por una
 * lista de "campos" — así agregar un campo nuevo a, por ejemplo, FAQ
 * es una línea, no un componente nuevo.
 */
import { refreshIcons } from '../../../../shared/utils/dom.utils.js';

function filaHtml(item, campos) {
  const id = item.id ?? '';
  const inputs = campos
    .map((c) => {
      const valor = (item[c.key] ?? '').toString().replace(/"/g, '&quot;');
      if (c.tipo === 'textarea') {
        return `<textarea data-field="${c.key}" placeholder="${c.placeholder || ''}" rows="2" class="w-full bg-ink border border-ink-line text-bone px-3 py-2 text-xs focus:outline-none focus:border-gold">${item[c.key] ?? ''}</textarea>`;
      }
      if (c.tipo === 'select') {
        const opciones = c.opciones
          .map((o) => `<option value="${o}" ${item[c.key] === o ? 'selected' : ''}>${o}</option>`)
          .join('');
        return `<select data-field="${c.key}" class="bg-ink border border-ink-line text-bone px-3 py-2 text-xs focus:outline-none focus:border-gold">${opciones}</select>`;
      }
      return `<input type="text" data-field="${c.key}" value="${valor}" placeholder="${c.placeholder || ''}" class="w-full bg-ink border border-ink-line text-bone px-3 py-2 text-xs focus:outline-none focus:border-gold">`;
    })
    .join('');

  return `<div class="flex items-start gap-2 p-3 border border-ink-line bg-ink" data-id="${id}">
    <div class="flex-1 grid gap-2 sm:grid-cols-${Math.min(campos.length, 3)}">${inputs}</div>
    <button data-action="eliminar-fila" class="text-bloqueado hover:bg-bloqueado hover:text-ink p-2 shrink-0 transition-colors"><i data-lucide="trash-2" class="w-3.5 h-3.5"></i></button>
  </div>`;
}

/** Pinta la lista de filas editables y engancha el borrado inmediato de cada una. */
export function renderListaEditable(container, items, campos, onEliminarFila) {
  container.innerHTML = items.map((item) => filaHtml(item, campos)).join('');
  refreshIcons();

  container.querySelectorAll('[data-id]').forEach((fila) => {
    fila.querySelector('[data-action="eliminar-fila"]').addEventListener('click', () => {
      onEliminarFila(fila.dataset.id || null, fila);
    });
  });
}

/** Agrega una fila vacía al final (para el botón "Agregar"). */
export function agregarFilaVacia(container, campos, onEliminarFila) {
  const div = document.createElement('div');
  div.innerHTML = filaHtml({}, campos);
  const fila = div.firstElementChild;
  container.appendChild(fila);
  refreshIcons();
  fila.querySelector('[data-action="eliminar-fila"]').addEventListener('click', () => {
    onEliminarFila(fila.dataset.id || null, fila);
  });
}

/** Lee todas las filas actualmente en el DOM y las convierte en objetos {id?, campo: valor, orden}. */
export function leerFilas(container, campos) {
  return Array.from(container.querySelectorAll('[data-id]')).map((fila, index) => {
    const obj = { orden: index, activo: true };
    if (fila.dataset.id) obj.id = Number(fila.dataset.id) || fila.dataset.id;
    campos.forEach((c) => {
      const input = fila.querySelector(`[data-field="${c.key}"]`);
      obj[c.key] = input ? input.value.trim() : '';
    });
    return obj;
  }).filter((obj) => {
    // Ignora filas completamente vacías (evita basura si tocaron "Agregar" de más).
    return campos.some((c) => obj[c.key]);
  });
}
