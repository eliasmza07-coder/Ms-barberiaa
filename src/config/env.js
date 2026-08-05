/**
 * config/env.js
 * Único lugar que lee variables de entorno (Vite las expone vía import.meta.env).
 * Ningún otro archivo del proyecto debe leer import.meta.env directamente.
 *
 * Los valores DEFAULT_* de abajo son los mismos que ya estaban escritos en
 * claro dentro del index.html original (la anon key de Supabase está
 * diseñada para ser pública — la protección real vive en las políticas RLS
 * del lado del servidor, no en ocultar esta key). Se mantienen como
 * fallback para que el proyecto funcione "out of the box" con
 * `npm install && npm run dev`, sin obligar a crear un .env primero — tal
 * como funcionaba el archivo único original. Si existe un .env con estas
 * variables (VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY,
 * VITE_EDGE_FUNCTION_NAME), ese valor tiene prioridad — útil para apuntar
 * a otro proyecto de Supabase (staging, otra barbería, etc.) sin tocar código.
 */
const DEFAULT_SUPABASE_URL = 'https://tvlziafugurgqstoekte.supabase.co';
const DEFAULT_SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR2bHppYWZ1Z3VyZ3FzdG9la3RlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU2NDg4NzMsImV4cCI6MjEwMTIyNDg3M30.9xHEUvsbJFoQDcZ74aAEQp--wl00sIVQ7HrDv6eibRI';
const DEFAULT_EDGE_FUNCTION_NAME = 'gestionar-reserva';

export const env = {
  SUPABASE_URL: import.meta.env.VITE_SUPABASE_URL || DEFAULT_SUPABASE_URL,
  SUPABASE_ANON_KEY: import.meta.env.VITE_SUPABASE_ANON_KEY || DEFAULT_SUPABASE_ANON_KEY,
  EDGE_FUNCTION_NAME: import.meta.env.VITE_EDGE_FUNCTION_NAME || DEFAULT_EDGE_FUNCTION_NAME,
};
