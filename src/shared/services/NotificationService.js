/**
 * shared/services/NotificationService.js
 * Punto único para notificaciones al usuario (hoy: mensajes inline de texto,
 * como en el proyecto original). Queda preparado para, a futuro, sumar
 * Toasts visuales sin tocar los controllers que ya lo usan.
 */
import { mostrarMensaje } from '../utils/dom.utils.js';

export const NotificationService = {
  info(elId, texto) { mostrarMensaje(elId, texto, 'info'); },
  success(elId, texto) { mostrarMensaje(elId, texto, 'ok'); },
  error(elId, texto) { mostrarMensaje(elId, texto, 'error'); },
};
