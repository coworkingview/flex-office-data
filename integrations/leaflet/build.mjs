import * as esbuild from 'esbuild';
import { mkdirSync, writeFileSync } from 'node:fs';

const leafletShim = `
const leaflet = globalThis.__LEAFLET_COWORKINGVIEW__;
export const LayerGroup = leaflet.LayerGroup;
export const Marker = leaflet.Marker;
export default leaflet;
`;

const result = await esbuild.build({
  entryPoints: ['src/index.js'],
  bundle: true,
  format: 'iife',
  globalName: 'leafletCoworkingView',
  target: 'es2020',
  write: false,
  legalComments: 'none',
  plugins: [
    {
      name: 'leaflet-global',
      setup(build) {
        build.onResolve({ filter: /^leaflet$/ }, () => ({
          path: 'leaflet',
          namespace: 'leaflet-global',
        }));
        build.onLoad({ filter: /.*/, namespace: 'leaflet-global' }, () => ({
          contents: leafletShim,
          loader: 'js',
        }));
      },
    },
  ],
});

const bundled = result.outputFiles[0].text.trim();
const umd = `/*! leaflet-coworkingview | MIT | https://coworkingview.com */
(function (root, factory) {
	if (typeof define === 'function' && define.amd) {
		define(['leaflet'], function (L) {
			var api = factory(L);
			L.coworkingView = api.coworkingView;
			return api;
		});
	} else if (typeof module === 'object' && module.exports) {
		var L = require('leaflet');
		var api = factory(L);
		L.coworkingView = api.coworkingView;
		module.exports = api;
	} else {
		var api = factory(root.L);
		root.L.coworkingView = api.coworkingView;
	}
})(typeof globalThis !== 'undefined' ? globalThis : this, function (L) {
	if (!L || !L.LayerGroup || !L.Marker) {
		throw new Error('Leaflet must be loaded before leaflet-coworkingview.');
	}
	var previous = globalThis.__LEAFLET_COWORKINGVIEW__;
	globalThis.__LEAFLET_COWORKINGVIEW__ = L;
	${bundled}
	if (previous === undefined) delete globalThis.__LEAFLET_COWORKINGVIEW__;
	else globalThis.__LEAFLET_COWORKINGVIEW__ = previous;
	return leafletCoworkingView;
});
`;

mkdirSync(new URL('./dist/', import.meta.url), { recursive: true });
writeFileSync(new URL('./dist/leaflet-coworkingview.js', import.meta.url), umd);
