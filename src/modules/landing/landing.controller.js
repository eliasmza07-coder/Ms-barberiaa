/**
 * modules/landing/landing.controller.js
 *
 * Orquesta toda la parte "de contenido" de la landing: hero, footer,
 * dirección/mapa, experiencia, redes sociales, galería, FAQ y reseñas.
 * Todo sale de content.service.js / reviews.service.js — nada queda
 * escrito fijo en el HTML, así el barbero puede cambiarlo todo desde el
 * panel sin tocar código.
 */
import { qs, refreshIcons } from '../../shared/utils/dom.utils.js';
import { ContentService } from '../content/content.service.js';
import { ReviewsService } from '../reviews/reviews.service.js';
import { aplicarTema } from '../../shared/utils/theme.utils.js';
import { iniciarScrollReveal, iniciarNavbarCompacto } from '../../shared/services/ScrollRevealService.js';
import { renderExperiencia } from './components/Experiencia/Experiencia.js';
import { renderGaleria } from './components/Galeria/Galeria.js';
import { renderFaq } from './components/Faq/Faq.js';
import { renderRedesSociales } from './components/Footer/Footer.js';
import { renderTestimonios, mostrarMensajeResena } from './components/Testimonios/Testimonios.js';

async function cargarConfiguracion() {
  const config = await ContentService.obtenerConfiguracion();

  aplicarTema(config);

  qs('heroUbicacionCorta').textContent = config.direccion_corta;
  qs('heroTitulo').innerHTML = `${config.hero_titulo}<br><span class="italic text-gold font-light">${config.hero_titulo_destacado}</span>`;
  qs('heroSubtitulo').textContent = config.hero_subtitulo;
  qs('direccionTexto').textContent = config.direccion;
  qs('mapaEmbed').src = config.mapa_embed_url;
  qs('footerTexto').textContent = config.footer_texto;
  qs('footerNombreNegocio').textContent = config.nombre_negocio;
  qs('navEslogan').textContent = config.eslogan;
}

async function cargarExperiencia() {
  const items = await ContentService.listarExperienciaActiva();
  renderExperiencia(qs('listaExperiencia'), items);
}

async function cargarRedes() {
  const redes = await ContentService.listarRedesActivas();
  renderRedesSociales(qs('listaRedesFooter'), redes);
  renderRedesSociales(qs('listaRedesUbicacion'), redes);
}

async function cargarGaleria() {
  const items = await ContentService.listarGaleriaActiva();
  renderGaleria(qs('galeria'), qs('listaGaleria'), items);
}

async function cargarFaq() {
  const items = await ContentService.listarFaqActiva();
  renderFaq(qs('faq'), qs('listaFaq'), items);
  refreshIcons();
}

async function cargarResenas() {
  const items = await ReviewsService.listarAprobadas();
  renderTestimonios(qs('resenas'), qs('listaResenas'), items);
}

async function handleEnviarResena() {
  const btn = qs('btnEnviarResena');
  const nombre = qs('resNombre').value.trim();
  const calificacion = qs('resCalificacion').value;
  const comentario = qs('resComentario').value.trim();

  btn.disabled = true;
  btn.textContent = 'Enviando...';
  try {
    await ReviewsService.enviar({ nombre, calificacion, comentario });
    mostrarMensajeResena('msgResena', '¡Gracias! Tu reseña se publicará luego de ser revisada.', 'ok');
    qs('resNombre').value = '';
    qs('resComentario').value = '';
  } catch (err) {
    mostrarMensajeResena('msgResena', err.message || 'Error al enviar la reseña.', 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = 'Enviar Reseña';
  }
}

export const LandingController = {
  async init() {
    refreshIcons();
    iniciarNavbarCompacto();
    await Promise.all([
      cargarConfiguracion(),
      cargarExperiencia(),
      cargarRedes(),
      cargarGaleria(),
      cargarFaq(),
      cargarResenas(),
    ]);
    qs('btnEnviarResena').addEventListener('click', handleEnviarResena);
    refreshIcons();
    // Se activa después de pintar el contenido dinámico, para que los
    // observadores ya encuentren las secciones con su tamaño final.
    iniciarScrollReveal();
  },

  // Expuesto para que el admin (tab Contenido) pida refrescar la landing
  // después de guardar cambios, y para RealtimeService.
  refrescarTodo() {
    return Promise.all([
      cargarConfiguracion(),
      cargarExperiencia(),
      cargarRedes(),
      cargarGaleria(),
      cargarFaq(),
      cargarResenas(),
    ]);
  },
};
