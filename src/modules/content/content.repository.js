/**
 * modules/content/content.repository.js
 * Acceso a las tablas de contenido editable: sitio_config, redes_sociales,
 * experiencia_items, galeria, faq (ver db/migrations/002_contenido_editable.sql).
 * Único punto de acceso a estas tablas — nada fuera de acá llama a
 * supabaseClient para estos datos.
 */
import { supabaseClient } from '../../config/supabaseClient.js';
import { BaseRepository } from '../../shared/repositories/BaseRepository.js';

export const sitioConfigRepository = {
  async obtener() {
    return supabaseClient.from('sitio_config').select('*').eq('id', 1).maybeSingle();
  },
  async guardar(payload) {
    return supabaseClient.from('sitio_config').update(payload).eq('id', 1);
  },
};

class RedesSocialesRepository extends BaseRepository {
  constructor() { super('redes_sociales'); }
  async listarOrdenadas() { return this.findAll({ column: 'orden', ascending: true }); }
}
export const redesSocialesRepository = new RedesSocialesRepository();

class ExperienciaRepository extends BaseRepository {
  constructor() { super('experiencia_items'); }
  async listarOrdenadas() { return this.findAll({ column: 'orden', ascending: true }); }
}
export const experienciaRepository = new ExperienciaRepository();

class GaleriaRepository extends BaseRepository {
  constructor() { super('galeria'); }
  async listarOrdenadas() { return this.findAll({ column: 'orden', ascending: true }); }
}
export const galeriaRepository = new GaleriaRepository();

class FaqRepository extends BaseRepository {
  constructor() { super('faq'); }
  async listarOrdenadas() { return this.findAll({ column: 'orden', ascending: true }); }
}
export const faqRepository = new FaqRepository();
