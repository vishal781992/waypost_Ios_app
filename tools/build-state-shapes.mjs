#!/usr/bin/env node
// Turns a US states GeoJSON into `Waypost/Resources/us-states.json` — the one asset the
// parks atlas needs and cannot ask MapKit for. No map SDK vends administrative
// boundaries, so filling Colorado when its last park is collected means having the shape
// of Colorado on disk.
//
//   1. Download the Census Bureau's own cartographic boundary file, the 1:20,000,000 cut —
//      it is the coarsest they publish and the right one for a map of the whole country:
//      https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_state_20m.zip
//      (or the GeoJSON mirror at github.com/PublicaMundi/MappingAPI, states.geojson)
//   2. node tools/build-state-shapes.mjs <input.geojson>
//   3. Rebuild. `xcodegen generate` is not needed — Resources is a directory reference.
//
// The output is deliberately dumb: a state's postal code against a list of rings, each
// ring a flat list of [longitude, latitude]. Longitude first, because that is the order
// GeoJSON uses and translating on the way in is where this sort of file usually goes
// wrong. `StateShapes` decodes it without a model.

import { readFileSync, writeFileSync } from "node:fs";

const NAMES = {
  Alabama: "AL", Alaska: "AK", Arizona: "AZ", Arkansas: "AR", California: "CA",
  Colorado: "CO", Connecticut: "CT", Delaware: "DE", Florida: "FL", Georgia: "GA",
  Hawaii: "HI", Idaho: "ID", Illinois: "IL", Indiana: "IN", Iowa: "IA", Kansas: "KS",
  Kentucky: "KY", Louisiana: "LA", Maine: "ME", Maryland: "MD", Massachusetts: "MA",
  Michigan: "MI", Minnesota: "MN", Mississippi: "MS", Missouri: "MO", Montana: "MT",
  Nebraska: "NE", Nevada: "NV", "New Hampshire": "NH", "New Jersey": "NJ",
  "New Mexico": "NM", "New York": "NY", "North Carolina": "NC", "North Dakota": "ND",
  Ohio: "OH", Oklahoma: "OK", Oregon: "OR", Pennsylvania: "PA", "Rhode Island": "RI",
  "South Carolina": "SC", "South Dakota": "SD", Tennessee: "TN", Texas: "TX", Utah: "UT",
  Vermont: "VT", Virginia: "VA", Washington: "WA", "West Virginia": "WV",
  Wisconsin: "WI", Wyoming: "WY", "District of Columbia": "DC",
  "American Samoa": "AS", "Virgin Islands": "VI", "Puerto Rico": "PR", Guam: "GU",
};

const source = process.argv[2];
if (!source) {
  console.error("usage: node tools/build-state-shapes.mjs <states.geojson>");
  process.exit(2);
}

const geo = JSON.parse(readFileSync(source, "utf8"));
const features = geo.features ?? [];
if (!features.length) {
  console.error(`no features in ${source} — is it a GeoJSON FeatureCollection?`);
  process.exit(1);
}

/** Every ring in a Polygon or a MultiPolygon, outer rings only. A state's holes are not
 *  worth the bytes at this scale, and MapKit draws a ring at a time regardless. */
function rings(geometry) {
  if (!geometry) return [];
  if (geometry.type === "Polygon") return [geometry.coordinates[0]];
  if (geometry.type === "MultiPolygon") return geometry.coordinates.map((p) => p[0]);
  return [];
}

/** Ramer–Douglas–Peucker, in degrees. A state drawn at the width of a phone does not need
 *  a coastline surveyed to the metre, and the file is a fifth of the size without one. */
function simplify(points, tolerance) {
  if (points.length < 3) return points;
  let far = 0;
  let best = 0;
  const [ax, ay] = points[0];
  const [bx, by] = points[points.length - 1];
  const dx = bx - ax;
  const dy = by - ay;
  const norm = dx * dx + dy * dy;
  for (let i = 1; i < points.length - 1; i++) {
    const [px, py] = points[i];
    let t = norm === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / norm;
    t = Math.max(0, Math.min(1, t));
    const qx = ax + t * dx;
    const qy = ay + t * dy;
    const d = (px - qx) ** 2 + (py - qy) ** 2;
    if (d > far) { far = d; best = i; }
  }
  if (far <= tolerance * tolerance) return [points[0], points[points.length - 1]];
  return [
    ...simplify(points.slice(0, best + 1), tolerance).slice(0, -1),
    ...simplify(points.slice(best), tolerance),
  ];
}

const out = {};
let dropped = [];
for (const feature of features) {
  const props = feature.properties ?? {};
  const name = props.NAME ?? props.name ?? props.STATE_NAME ?? "";
  const code = props.STUSPS ?? props.STATE_ABBR ?? NAMES[name];
  if (!code) { dropped.push(name || "(unnamed)"); continue; }

  const shape = rings(feature.geometry)
    // A sliver island adds a ring and no information at this scale.
    .filter((ring) => ring.length >= 8)
    .map((ring) => simplify(ring, 0.02).map(([lon, lat]) => [+lon.toFixed(4), +lat.toFixed(4)]))
    .filter((ring) => ring.length >= 3);

  if (shape.length) out[code] = shape;
}

const json = JSON.stringify(out);
writeFileSync("Waypost/Resources/us-states.json", json);

const points = Object.values(out).reduce((n, s) => n + s.reduce((m, r) => m + r.length, 0), 0);
console.log(`us-states.json — ${Object.keys(out).length} states, ${points} points, ` +
            `${(json.length / 1024).toFixed(0)} KB`);
if (dropped.length) console.log(`skipped (no postal code): ${dropped.join(", ")}`);
