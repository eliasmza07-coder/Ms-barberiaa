/**
 * shared/utils/currency.utils.js
 * Migrado 1:1 desde formatoGs() del index.html original.
 */
export function formatoGs(num) {
  return Number(num).toLocaleString('es-PY') + ' Gs';
}
