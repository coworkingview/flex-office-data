import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { runInNewContext } from 'node:vm';
import { describe, expect, it } from 'vitest';
import L from 'leaflet';

describe('UMD build', () => {
  it('registers L.coworkingView.layer when Leaflet is already on the page', () => {
    const source = readFileSync(join(process.cwd(), 'dist/leaflet-coworkingview.js'), 'utf8');
    const context = {
      L,
      window,
      document,
      console,
      setTimeout,
      clearTimeout,
      URL,
      fetch,
      Headers,
      Response,
      AbortSignal,
      AbortController,
    };
    runInNewContext(source, context, { filename: 'leaflet-coworkingview.js' });
    expect(typeof context.L.coworkingView.layer).toBe('function');
    const group = context.L.coworkingView.layer();
    expect(group).toBeInstanceOf(L.LayerGroup);
    expect(group.options.attribution).toContain('https://coworkingview.com');
    expect(group.options.attribution).toContain('CC BY 4.0');
  });
});
