/**
 * shared/utils/whatsapp.utils.js
 * Arma links de WhatsApp (wa.me) para que el barbero pueda avisarle al
 * cliente con un clic cuando confirma o cancela un turno — no depende de
 * ningún servicio de email/SMS de terceros, usa lo que ya tenés (WhatsApp).
 */

/** Limpia un teléfono paraguayo tipeado de cualquier forma (0975..., 595975..., con espacios/guiones) a formato wa.me. */
export function telefonoWhatsapp(telefono) {
  let limpio = (telefono || '').replace(/\D/g, '');
  if (!limpio) return '';
  if (limpio.startsWith('0')) limpio = '595' + limpio.slice(1);
  else if (!limpio.startsWith('595')) limpio = '595' + limpio;
  return limpio;
}

/** Abre WhatsApp (web o app) en una pestaña nueva con el mensaje ya escrito, listo para enviar. */
export function abrirWhatsapp(telefono, mensaje) {
  const tel = telefonoWhatsapp(telefono);
  if (!tel) return;
  const url = `https://wa.me/${tel}?text=${encodeURIComponent(mensaje)}`;
  window.open(url, '_blank', 'noopener');
}

export function mensajeConfirmacion(turno) {
  return `Hola ${turno.cliente_nombre}! Tu turno para *${turno.servicio_nombre}* el ${turno.fecha} a las ${turno.hora.slice(0, 5)} fue *confirmado* ✅. Te esperamos en MS Barbería y Peluquería.`;
}

export function mensajeCancelacion(turno) {
  return `Hola ${turno.cliente_nombre}, tu turno para *${turno.servicio_nombre}* el ${turno.fecha} a las ${turno.hora.slice(0, 5)} fue *cancelado*. Cualquier consulta escribinos por acá.`;
}
