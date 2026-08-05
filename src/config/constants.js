/**
 * config/constants.js
 * Constantes compartidas por todo el proyecto: estados, defaults, etc.
 * Mantiene los mismos valores que ya usa la base de datos actual — no son
 * "nuevos" estados, son los que ya existen en la tabla `turnos.estado`.
 */

export const ESTADO_TURNO = {
  PENDIENTE: 'pendiente',
  CONFIRMADO: 'confirmado',
  CANCELADO: 'cancelado',
};

export const ESTADO_SLOT = {
  LIBRE: 'libre',
  RESERVADO: 'reservado',
  BLOQUEADO: 'bloqueado',
  PASADO: 'pasado',
};

// Config de jornada por defecto si no hay override en `config_jornada` para la fecha.
export const JORNADA_DEFAULT = { apertura: 8, cierre: 20, intervalo: 15 };

// Servicios de fallback si la tabla `servicios` está vacía o falla la consulta.
// (idéntico al fallback que ya existía embebido en el index.html original)
export const SERVICIOS_FALLBACK = [
  { id: 'corte', nombre: 'Corte Masculino', precio: 40000, duracion: 30, desc: 'Corte clásico o moderno con navaja.' },
  { id: 'barba', nombre: 'Perfilado de Barba', precio: 25000, duracion: 30, desc: 'Diseño con toalla caliente.' },
  { id: 'corte_barba', nombre: 'Corte + Barba', precio: 60000, duracion: 60, desc: 'La experiencia completa.' },
];

export const NEGOCIO = {
  nombre: 'MS Barbería y Peluquería',
  ubicacionCorta: 'Yukyry · Luque · Paraguay',
  ubicacionLarga: 'Barrio Yukyry, Luque, Paraguay',
};
