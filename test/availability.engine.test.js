/**
 * test/availability.engine.test.js
 *
 * Se corre con el runner nativo de Node (no hace falta instalar nada):
 *
 *     node --test test/
 *
 * Cada test es uno de los "casos extremos" del pliego. Si mañana alguien
 * toca el motor y rompe una de estas reglas, el test lo grita antes de que
 * lo descubra un cliente que llegó a un horario que no existía.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  calcularDisponibilidadDia,
  estadoDelDia,
  fusionarRangos,
  seSolapan,
  MOTIVO,
  MOTIVO_DIA,
} from '../src/modules/availability/availability.engine.js';
import { aMinutos, aHora, sumarDias, diaSemana, ahoraEnZona } from '../src/shared/utils/datetime.utils.js';

/** Caso base reutilizable: mañana, jornada 08:00–12:00 y 14:00–20:00, intervalo 15. */
function base(extra = {}) {
  return {
    fecha: '2026-08-10',
    hoy: '2026-08-05',
    minutosAhora: aMinutos('10:00'),
    diasHastaFecha: 5,
    jornadas: [
      { inicio: aMinutos('08:00'), fin: aMinutos('12:00') },
      { inicio: aMinutos('14:00'), fin: aMinutos('20:00') },
    ],
    intervalo: 15,
    duracion: 30,
    anticipacionMin: 30,
    anticipacionMaxDias: 60,
    ...extra,
  };
}

const horas = (r) => r.slots.filter((s) => s.disponible).map((s) => aHora(s.hora));

test('genera la grilla dinámicamente según el intervalo', () => {
  const r = calcularDisponibilidadDia(base({ intervalo: 30 }));
  assert.equal(horas(r)[0], '08:00');
  assert.ok(horas(r).includes('08:30'));
  assert.ok(!horas(r).includes('08:15'));
});

test('nunca ofrece un horario donde el servicio no termina antes del cierre', () => {
  // Jornada única 08:00–09:00, servicio de 30 min → último inicio válido: 08:30.
  const r = calcularDisponibilidadDia(
    base({ jornadas: [{ inicio: aMinutos('08:00'), fin: aMinutos('09:00') }] })
  );
  assert.deepEqual(horas(r), ['08:00', '08:15', '08:30']);
});

test('respeta la pausa del mediodía (jornada partida)', () => {
  const r = calcularDisponibilidadDia(base({ duracion: 60 }));
  const h = horas(r);
  assert.ok(h.includes('11:00'), 'el último de la mañana debe entrar');
  assert.ok(!h.includes('11:15'), 'no puede empezar algo que invade la pausa');
  assert.ok(h.includes('14:00'), 'la tarde arranca de nuevo en la apertura');
});

test('servicios combinados: corte 30 + barba 20 = bloque de 50 min', () => {
  const r = calcularDisponibilidadDia(
    base({
      duracion: 50,
      jornadas: [{ inicio: aMinutos('09:00'), fin: aMinutos('10:00') }],
    })
  );
  assert.deepEqual(horas(r), ['09:00', '09:10'].slice(0, 1)); // con intervalo 15: solo 09:00
});

test('los márgenes de preparación y limpieza bloquean tiempo real', () => {
  // Corte 30 + 5 de limpieza = 35 min ocupados. Jornada 09:00–09:35 → entra justo uno.
  const r = calcularDisponibilidadDia(
    base({
      duracion: 30,
      margenDespues: 5,
      jornadas: [{ inicio: aMinutos('09:00'), fin: aMinutos('09:35') }],
    })
  );
  assert.deepEqual(horas(r), ['09:00']);
  assert.equal(r.slots[0].duracionTotal, 35);
});

test('una cita existente bloquea todos los slots que se solapan, aunque no estén alineados a la grilla', () => {
  // Turno de 09:10 a 09:40 (creado a mano por el barbero, fuera de la grilla de 15).
  const r = calcularDisponibilidadDia(
    base({
      jornadas: [{ inicio: aMinutos('09:00'), fin: aMinutos('11:00') }],
      ocupaciones: [{ inicio: aMinutos('09:10'), fin: aMinutos('09:40') }],
      incluirNoDisponibles: true,
    })
  );
  const porHora = Object.fromEntries(r.slots.map((s) => [aHora(s.hora), s]));
  assert.equal(porHora['09:00'].disponible, false, '09:00–09:30 pisa la cita');
  assert.equal(porHora['09:15'].disponible, false);
  assert.equal(porHora['09:30'].disponible, false);
  assert.equal(porHora['09:45'].disponible, true, 'después de las 09:40 vuelve a haber lugar');
  assert.equal(porHora['09:15'].motivo, MOTIVO.OCUPADO);
});

test('distingue bloqueo manual de cita ocupada', () => {
  const r = calcularDisponibilidadDia(
    base({
      jornadas: [{ inicio: aMinutos('14:00'), fin: aMinutos('17:00') }],
      bloqueos: [{ inicio: aMinutos('14:00'), fin: aMinutos('16:00') }],
      incluirNoDisponibles: true,
    })
  );
  const primero = r.slots[0];
  assert.equal(primero.motivo, MOTIVO.BLOQUEADO);
  assert.ok(horas(r).includes('16:00'));
});

test('hoy: oculta lo pasado y aplica la anticipación mínima', () => {
  // Son las 14:20, anticipación 30 min → el primer horario ofrecible es 15:00.
  const r = calcularDisponibilidadDia(
    base({
      fecha: '2026-08-05',
      hoy: '2026-08-05',
      diasHastaFecha: 0,
      minutosAhora: aMinutos('14:20'),
      anticipacionMin: 30,
      jornadas: [{ inicio: aMinutos('08:00'), fin: aMinutos('20:00') }],
    })
  );
  const h = horas(r);
  assert.ok(!h.includes('14:00'), 'horario pasado');
  assert.ok(!h.includes('14:30'), 'no llega a la anticipación mínima');
  assert.ok(!h.includes('14:45'));
  assert.equal(h[0], '15:00');
});

test('el barbero puede saltear la anticipación para una cita hecha en el local', () => {
  const r = calcularDisponibilidadDia(
    base({
      fecha: '2026-08-05',
      hoy: '2026-08-05',
      diasHastaFecha: 0,
      minutosAhora: aMinutos('14:20'),
      ignorarAnticipacion: true,
      jornadas: [{ inicio: aMinutos('08:00'), fin: aMinutos('20:00') }],
    })
  );
  assert.equal(horas(r)[0], '14:30');
});

test('día cerrado o sin jornada configurada no ofrece nada', () => {
  assert.equal(calcularDisponibilidadDia(base({ cerrado: true })).motivoDia, MOTIVO_DIA.CERRADO);
  assert.equal(calcularDisponibilidadDia(base({ jornadas: [] })).motivoDia, MOTIVO_DIA.CERRADO);
});

test('no deja reservar más allá del límite de anticipación', () => {
  const r = calcularDisponibilidadDia(base({ diasHastaFecha: 61, anticipacionMaxDias: 60 }));
  assert.equal(r.motivoDia, MOTIVO_DIA.FUERA_DE_RANGO);
});

test('fecha pasada nunca abre', () => {
  const r = calcularDisponibilidadDia(base({ fecha: '2026-08-01', hoy: '2026-08-05' }));
  assert.equal(r.motivoDia, MOTIVO_DIA.PASADO);
});

test('día lleno se reporta como sin_cupo, no como cerrado', () => {
  const r = calcularDisponibilidadDia(
    base({
      jornadas: [{ inicio: aMinutos('09:00'), fin: aMinutos('10:00') }],
      ocupaciones: [{ inicio: aMinutos('09:00'), fin: aMinutos('10:00') }],
    })
  );
  assert.equal(r.motivoDia, MOTIVO_DIA.SIN_CUPO);
  assert.equal(r.abierto, true);
});

test('estadoDelDia sirve para pintar la tira de días', () => {
  const e = estadoDelDia(base());
  assert.equal(e.estado, MOTIVO_DIA.DISPONIBLE);
  assert.ok(e.cupos > 10);
});

test('fusionarRangos une bloqueos contiguos y descarta basura', () => {
  assert.deepEqual(
    fusionarRangos([
      { inicio: 60, fin: 120 },
      { inicio: 100, fin: 180 },
      { inicio: 300, fin: 300 },
      { inicio: 400, fin: 350 },
    ]),
    [{ inicio: 60, fin: 180 }]
  );
});

test('seSolapan trata los rangos como semiabiertos: fin == inicio no choca', () => {
  assert.equal(seSolapan(0, 30, 30, 60), false);
  assert.equal(seSolapan(0, 31, 30, 60), true);
});

// ---------- Zona horaria ----------

test('la fecha del negocio no depende del huso del navegador', () => {
  // 2026-08-06 00:30 UTC = 2026-08-05 21:30 en Asunción (UTC-3). El sistema
  // viejo (toISOString) decía "6 de agosto" y escondía los turnos de esa noche.
  const instante = new Date('2026-08-06T00:30:00Z');
  const enPY = ahoraEnZona('America/Asuncion', instante);
  assert.equal(enPY.fecha, '2026-08-05', 'sigue siendo el día 5 para el negocio');
  assert.equal(aHora(enPY.minutos), '21:30');
  assert.notEqual(enPY.fecha, instante.toISOString().slice(0, 10));
});

test('sumarDias y diaSemana son estables', () => {
  assert.equal(sumarDias('2026-08-31', 1), '2026-09-01');
  assert.equal(sumarDias('2026-01-01', -1), '2025-12-31');
  assert.equal(diaSemana('2026-08-05'), 3); // miércoles
});
