import { readFileSync } from 'node:fs';

/**
 * Reads KEY=VALUE pairs from a dotenv-style file (comments and blank lines ignored,
 * optional single/double quotes stripped). Only the MCP server process reads this file:
 * values are sent to the app but never returned to the client.
 */
export function loadEnvFile(path) {
  const pairs = new Map();
  const text = readFileSync(path, 'utf8');
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 1) continue;
    const key = line.slice(0, eq).trim().replace(/^export\s+/, '');
    let value = line.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    pairs.set(key, value);
  }
  return pairs;
}

/** Keys defined in the file (names only; safe to report). */
export function envKeys(path) {
  return [...loadEnvFile(path).keys()];
}
