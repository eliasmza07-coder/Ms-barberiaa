/**
 * modules/content/content.service.js
 * Reglas de negocio del contenido editable del sitio. La landing lo usa
 * para pintarse (solo lectura); el admin lo usa para editar (lectura +
 * escritura). Todo con fallback a los mismos textos que ya tenía el HTML
 * original, por si la tabla está vacía o falla la consulta.
 */
import {
  sitioConfigRepository,
  redesSocialesRepository,
  experienciaRepository,
  galeriaRepository,
  faqRepository,
} from './content.repository.js';

const CONFIG_FALLBACK = {
  nombre_negocio: 'MS Barbería y Peluquería',
  eslogan: 'Studio & Peluquería',
  hero_titulo: 'El oficio del corte,',
  hero_titulo_destacado: 'hecho a mano.',
  hero_subtitulo:
    'Barbería tradicional con estándar de estudio: navaja al detalle, atención dedicada y gestión 100% autónoma para asegurar tu espacio sin esperas.',
  direccion: 'Barrio Yukyry, Luque, Paraguay',
  direccion_corta: 'Yukyry · Luque · Paraguay',
  mapa_embed_url: 'https://www.google.com/maps?q=MS%20Barber%C3%ADa%20y%20Peluquer%C3%ADa%2C%20Luque%2C%20Paraguay&output=embed',
  footer_texto: '© 2026 Yukyry, Luque, Paraguay. Todos los derechos reservados.',
  color_fondo: '#0A0A0A',
  color_superficie: '#1A1A1A',
  color_texto: '#F5F5F4',
  color_acento: '#E8E8E6',
};

export const ContentService = {
  async obtenerConfiguracion() {
    try {
      const { data } = await sitioConfigRepository.obtener();
      return data || CONFIG_FALLBACK;
    } catch (e) {
      console.error('[ContentService] error al leer sitio_config', e);
      return CONFIG_FALLBACK;
    }
  },

  async guardarConfiguracion(payload) {
    const { error } = await sitioConfigRepository.guardar(payload);
    if (error) throw error;
  },

  async listarRedesActivas() {
    try {
      const { data } = await redesSocialesRepository.listarOrdenadas();
      return (data || []).filter((r) => r.activo);
    } catch (e) { return []; }
  },
  async listarRedesTodas() {
    const { data } = await redesSocialesRepository.listarOrdenadas();
    return data || [];
  },
  guardarRed(payload) { return redesSocialesRepository.upsert(payload); },
  eliminarRed(id) { return redesSocialesRepository.remove(id); },

  async listarExperienciaActiva() {
    try {
      const { data } = await experienciaRepository.listarOrdenadas();
      return (data || []).filter((e) => e.activo);
    } catch (e) { return []; }
  },
  async listarExperienciaTodas() {
    const { data } = await experienciaRepository.listarOrdenadas();
    return data || [];
  },
  guardarExperiencia(payload) { return experienciaRepository.upsert(payload); },
  eliminarExperiencia(id) { return experienciaRepository.remove(id); },

  async listarGaleriaActiva() {
    try {
      const { data } = await galeriaRepository.listarOrdenadas();
      return (data || []).filter((g) => g.activo);
    } catch (e) { return []; }
  },
  async listarGaleriaTodas() {
    const { data } = await galeriaRepository.listarOrdenadas();
    return data || [];
  },
  guardarGaleria(payload) { return galeriaRepository.upsert(payload); },
  eliminarGaleria(id) { return galeriaRepository.remove(id); },

  async listarFaqActiva() {
    try {
      const { data } = await faqRepository.listarOrdenadas();
      return (data || []).filter((f) => f.activo);
    } catch (e) { return []; }
  },
  async listarFaqTodas() {
    const { data } = await faqRepository.listarOrdenadas();
    return data || [];
  },
  guardarFaq(payload) { return faqRepository.upsert(payload); },
  eliminarFaq(id) { return faqRepository.remove(id); },
};
