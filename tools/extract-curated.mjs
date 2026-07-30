// Convert the Claude Design prototype's field library into the JSON the app bundles.
//
// The design file (`Waypost Mobile.dc.html`) carries its data as class properties on the
// prototype component — CITIES, P (parks), LEGS, DAYS, PASSPORT. This lifts those blocks
// out verbatim and evaluates them, so the app's colours, copy, day plans and permit notes
// are the designer's, not a re-typing of them.
//
//   node tools/extract-curated.mjs <path-to-Waypost Mobile.dc.html>
//
// Writes Waypost/Resources/curated.json.
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = process.argv[2];
if (!source) {
  console.error('usage: node tools/extract-curated.mjs "<path to Waypost Mobile.dc.html>"');
  process.exit(1);
}
const src = readFileSync(source, 'utf8');

/// Reads `  NAME = { … }` (or `[ … ]`) by balancing brackets — the blocks contain
/// nested objects, strings with braces and comments, so a regex would not survive.
function grab(name, open, close) {
  const start = src.indexOf(`\n  ${name} = ${open}`);
  if (start < 0) throw new Error(`missing ${name}`);
  let i = src.indexOf(open, start);
  let depth = 0, end = i;
  for (; end < src.length; end++) {
    const ch = src[end];
    if (ch === open) depth++;
    else if (ch === close) { depth--; if (!depth) break; }
  }
  return src.slice(i, end + 1);
}

const out = {};
for (const [name, open, close] of [
  ['CITIES', '[', ']'], ['P', '{', '}'], ['LEGS', '[', ']'],
  ['DAYS', '[', ']'], ['PASSPORT', '[', ']'],
]) {
  out[name] = new Function('return (' + grab(name, open, close) + ')')();
}

const target = resolve(here, '..', 'Waypost', 'Resources', 'curated.json');
writeFileSync(target, JSON.stringify(out));
console.log(
  `parks ${Object.keys(out.P).length} · legs ${out.LEGS.length} · days ${out.DAYS.length} · ` +
  `passport ${out.PASSPORT.length} · cities ${out.CITIES.length} -> ${target}`
);
