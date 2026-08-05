/**
 * shared/state/store.js
 * Estado mínimo compartido entre módulos (equivalente a las variables
 * globales SERVICIOS, servicioSeleccionado, horaSeleccionada, etc. del
 * index.html original, pero encapsuladas en vez de sueltas en `window`).
 */
export const store = {
  servicios: [],
  servicioSeleccionado: null,
  horaSeleccionada: null,
  turnosDia: [],
  horasBloqueadasDia: [],
  diaBloqueado: false,
  configJornadaActual: { apertura: 8, cierre: 20, intervalo: 15 },
};
