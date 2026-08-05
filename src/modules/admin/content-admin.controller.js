/**
 * modules/admin/content-admin.controller.js
 * Orquesta el tab "Contenido" del panel: datos generales del negocio,
 * redes sociales, tarjetas de experiencia, galería y FAQ. Este es el
 * tab que le da al barbero autonomía real — todo lo que antes requería
 * pedirle un cambio al programador, ahora se edita acá.
 */
import { qs, refreshIcons } from '../../shared/utils/dom.utils.js';
import { ContentService } from '../content/content.service.js';
import { ReviewsService } from '../reviews/reviews.service.js';
import { aplicarTema, TEMA_DEFAULT } from '../../shared/utils/theme.utils.js';
import { renderListaEditable, agregarFilaVacia, leerFilas } from './components/ContenidoAdmin/ContenidoAdmin.js';

const CAMPOS_REDES = [
  { key: 'plataforma', tipo: 'select', opciones: ['whatsapp', 'instagram', 'facebook', 'tiktok', 'maps'] },
  { key: 'url', placeholder: 'https://...' },
];
const CAMPOS_EXPERIENCIA = [
  { key: 'icono', placeholder: 'ícono lucide (ej: shield-check)' },
  { key: 'titulo', placeholder: 'Título' },
  { key: 'descripcion', tipo: 'textarea', placeholder: 'Descripción' },
];
const CAMPOS_GALERIA = [
  { key: 'imagen_url', placeholder: 'https://... (URL de la imagen)' },
  { key: 'descripcion', placeholder: 'Descripción (opcional)' },
];
const CAMPOS_FAQ = [
  { key: 'pregunta', placeholder: 'Pregunta' },
  { key: 'respuesta', tipo: 'textarea', placeholder: 'Respuesta' },
];

// ---------- Datos generales ----------
async function cargarConfigGeneral() {
  const c = await ContentService.obtenerConfiguracion();
  qs('cfgNombreNegocio').value = c.nombre_negocio || '';
  qs('cfgEslogan').value = c.eslogan || '';
  qs('cfgHeroTitulo').value = c.hero_titulo || '';
  qs('cfgHeroTituloDestacado').value = c.hero_titulo_destacado || '';
  qs('cfgHeroSubtitulo').value = c.hero_subtitulo || '';
  qs('cfgDireccion').value = c.direccion || '';
  qs('cfgDireccionCorta').value = c.direccion_corta || '';
  qs('cfgTelefono').value = c.telefono || '';
  qs('cfgWhatsapp').value = c.whatsapp || '';
  qs('cfgMapaUrl').value = c.mapa_embed_url || '';
  qs('cfgFooterTexto').value = c.footer_texto || '';
}

async function guardarConfigGeneral() {
  try {
    await ContentService.guardarConfiguracion({
      nombre_negocio: qs('cfgNombreNegocio').value.trim(),
      eslogan: qs('cfgEslogan').value.trim(),
      hero_titulo: qs('cfgHeroTitulo').value.trim(),
      hero_titulo_destacado: qs('cfgHeroTituloDestacado').value.trim(),
      hero_subtitulo: qs('cfgHeroSubtitulo').value.trim(),
      direccion: qs('cfgDireccion').value.trim(),
      direccion_corta: qs('cfgDireccionCorta').value.trim(),
      telefono: qs('cfgTelefono').value.trim(),
      whatsapp: qs('cfgWhatsapp').value.trim(),
      mapa_embed_url: qs('cfgMapaUrl').value.trim(),
      footer_texto: qs('cfgFooterTexto').value.trim(),
    });
    alert('¡Datos generales actualizados! Los cambios ya se ven en el sitio.');
  } catch (err) {
    alert('Error al guardar: ' + (err.message || 'desconocido'));
  }
}

// ---------- Fábrica genérica para las 4 listas (redes/experiencia/galería/faq) ----------
function crearSeccionLista({ containerId, btnAgregarId, btnGuardarId, campos, listar, guardar, eliminar }) {
  const container = qs(containerId);

  async function eliminarFila(id, filaEl) {
    filaEl.remove();
    if (id) {
      try { await eliminar(id); } catch (err) { alert('Error al eliminar: ' + (err.message || '')); }
    }
  }

  async function cargar() {
    const items = await listar();
    renderListaEditable(container, items, campos, eliminarFila);
  }

  async function guardarTodo() {
    const filas = leerFilas(container, campos);
    try {
      await Promise.all(filas.map((f) => guardar(f)));
      await cargar(); // re-pinta con los ids reales que asignó la base
      alert('¡Guardado!');
    } catch (err) {
      alert('Error al guardar: ' + (err.message || 'desconocido'));
    }
  }

  qs(btnAgregarId).addEventListener('click', () => agregarFilaVacia(container, campos, eliminarFila));
  qs(btnGuardarId).addEventListener('click', guardarTodo);

  return { cargar };
}

// ---------- Reseñas (moderación: aprobar / eliminar) ----------
async function cargarResenasAdmin() {
  const container = qs('listaResenasAdmin');
  const items = await ReviewsService.listarTodas();

  if (items.length === 0) {
    container.innerHTML = `<p class="text-bone-dim text-xs font-mono text-center py-4">Todavía no hay reseñas.</p>`;
    return;
  }

  container.innerHTML = items
    .map((r) => {
      const estrellas = '★'.repeat(r.calificacion) + '☆'.repeat(5 - r.calificacion);
      const estado = r.aprobada
        ? `<span class="text-libre">Publicada</span>`
        : `<span class="text-pendiente">Pendiente</span>`;
      return `<div class="flex items-start justify-between gap-3 p-3 border border-ink-line bg-ink" data-id="${r.id}">
        <div class="flex-1">
          <p class="text-gold text-xs mb-1">${estrellas} · ${estado}</p>
          <p class="text-bone text-xs font-semibold mb-0.5">${r.cliente_nombre}</p>
          <p class="text-bone-dim text-xs">${r.comentario}</p>
        </div>
        <div class="flex flex-col gap-1.5 shrink-0">
          ${!r.aprobada ? `<button data-action="aprobar" class="bg-libre text-ink px-3 py-1.5 text-[10px] uppercase tracking-widest font-semibold">Aprobar</button>` : ''}
          <button data-action="eliminar" class="border border-bloqueado text-bloqueado hover:bg-bloqueado hover:text-ink px-3 py-1.5 text-[10px] uppercase tracking-widest font-mono">Eliminar</button>
        </div>
      </div>`;
    })
    .join('');

  container.querySelectorAll('[data-id]').forEach((row) => {
    const id = row.dataset.id;
    row.querySelector('[data-action="aprobar"]')?.addEventListener('click', async () => {
      await ReviewsService.aprobar(id);
      cargarResenasAdmin();
    });
    row.querySelector('[data-action="eliminar"]').addEventListener('click', async () => {
      if (!confirm('¿Eliminar esta reseña?')) return;
      await ReviewsService.rechazar(id);
      cargarResenasAdmin();
    });
  });
}

// ---------- Apariencia (colores en vivo) ----------
const CAMPOS_COLOR = [
  { input: 'apFondo', campo: 'color_fondo' },
  { input: 'apSuperficie', campo: 'color_superficie' },
  { input: 'apTexto', campo: 'color_texto' },
  { input: 'apAcento', campo: 'color_acento' },
];

async function cargarApariencia() {
  const c = await ContentService.obtenerConfiguracion();
  CAMPOS_COLOR.forEach(({ input, campo }) => {
    qs(input).value = c[campo] || TEMA_DEFAULT[campo];
  });
}

function previsualizarApariencia() {
  const valores = {};
  CAMPOS_COLOR.forEach(({ input, campo }) => { valores[campo] = qs(input).value; });
  aplicarTema(valores);
}

async function guardarApariencia() {
  const valores = {};
  CAMPOS_COLOR.forEach(({ input, campo }) => { valores[campo] = qs(input).value; });
  try {
    await ContentService.guardarConfiguracion(valores);
    qs('msgApariencia').textContent = '¡Colores guardados! Ya se ven así para todos.';
    qs('msgApariencia').className = 'text-xs mt-3 font-mono text-libre';
  } catch (err) {
    qs('msgApariencia').textContent = 'Error al guardar: ' + (err.message || '');
    qs('msgApariencia').className = 'text-xs mt-3 font-mono text-bloqueado';
  }
}

function restaurarApariencia() {
  CAMPOS_COLOR.forEach(({ input, campo }) => { qs(input).value = TEMA_DEFAULT[campo]; });
  previsualizarApariencia();
}

export const ContentAdminController = {
  init() {
    qs('btnGuardarConfigGeneral').addEventListener('click', guardarConfigGeneral);

    CAMPOS_COLOR.forEach(({ input }) => {
      qs(input).addEventListener('input', previsualizarApariencia);
    });
    qs('btnGuardarApariencia').addEventListener('click', guardarApariencia);
    qs('btnRestaurarApariencia').addEventListener('click', restaurarApariencia);

    this.redes = crearSeccionLista({
      containerId: 'listaRedesAdmin',
      btnAgregarId: 'btnAgregarRed',
      btnGuardarId: 'btnGuardarRedes',
      campos: CAMPOS_REDES,
      listar: () => ContentService.listarRedesTodas(),
      guardar: (f) => ContentService.guardarRed(f),
      eliminar: (id) => ContentService.eliminarRed(id),
    });

    this.experiencia = crearSeccionLista({
      containerId: 'listaExperienciaAdmin',
      btnAgregarId: 'btnAgregarExperiencia',
      btnGuardarId: 'btnGuardarExperiencia',
      campos: CAMPOS_EXPERIENCIA,
      listar: () => ContentService.listarExperienciaTodas(),
      guardar: (f) => ContentService.guardarExperiencia(f),
      eliminar: (id) => ContentService.eliminarExperiencia(id),
    });

    this.galeria = crearSeccionLista({
      containerId: 'listaGaleriaAdmin',
      btnAgregarId: 'btnAgregarGaleria',
      btnGuardarId: 'btnGuardarGaleria',
      campos: CAMPOS_GALERIA,
      listar: () => ContentService.listarGaleriaTodas(),
      guardar: (f) => ContentService.guardarGaleria(f),
      eliminar: (id) => ContentService.eliminarGaleria(id),
    });

    this.faq = crearSeccionLista({
      containerId: 'listaFaqAdmin',
      btnAgregarId: 'btnAgregarFaq',
      btnGuardarId: 'btnGuardarFaq',
      campos: CAMPOS_FAQ,
      listar: () => ContentService.listarFaqTodas(),
      guardar: (f) => ContentService.guardarFaq(f),
      eliminar: (id) => ContentService.eliminarFaq(id),
    });
  },

  async cargarTodo() {
    await Promise.all([
      cargarConfigGeneral(),
      this.redes.cargar(),
      this.experiencia.cargar(),
      this.galeria.cargar(),
      this.faq.cargar(),
      cargarResenasAdmin(),
      cargarApariencia(),
    ]);
  },
};
