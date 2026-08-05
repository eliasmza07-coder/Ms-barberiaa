/**
 * config/supabaseClient.js
 *
 * ÚNICO archivo de todo el proyecto que puede crear el cliente de Supabase.
 * Ningún componente, controller o service debe importar '@supabase/supabase-js'
 * directamente: todos pasan por acá, y de acá solo lo consumen los repositories
 * (shared/repositories) y algunos services muy puntuales (auth, realtime).
 */
import { createClient } from '@supabase/supabase-js';
import { env } from './env.js';

export const supabaseClient = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY);

export const EDGE_FUNCTION_URL = `${env.SUPABASE_URL}/functions/v1/${env.EDGE_FUNCTION_NAME}`;
