/**
 * modules/reviews/reviews.service.js
 * Reglas de negocio de reseñas: envío público (queda pendiente de
 * aprobación) y moderación desde el admin.
 */
import { reviewsRepository } from './reviews.repository.js';

export const ReviewsService = {
  async listarAprobadas() {
    try {
      const { data } = await reviewsRepository.listarAprobadas();
      return data || [];
    } catch (e) {
      console.error('[ReviewsService] error al listar reseñas', e);
      return [];
    }
  },

  async listarTodas() {
    const { data, error } = await reviewsRepository.listarTodas();
    if (error) throw error;
    return data || [];
  },

  async enviar({ nombre, calificacion, comentario }) {
    if (!nombre || !comentario) throw new Error('Completá tu nombre y comentario.');
    const calNum = Number(calificacion);
    if (!calNum || calNum < 1 || calNum > 5) throw new Error('Elegí una calificación de 1 a 5.');
    const { error } = await reviewsRepository.enviarPublica({
      cliente_nombre: nombre,
      calificacion: calNum,
      comentario,
    });
    if (error) throw error;
  },

  async aprobar(id) {
    const { error } = await reviewsRepository.aprobar(id);
    if (error) throw error;
  },

  async rechazar(id) {
    const { error } = await reviewsRepository.rechazar(id);
    if (error) throw error;
  },
};
