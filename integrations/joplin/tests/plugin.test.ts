import * as fs from 'fs';
import * as path from 'path';

import { PLUGIN_VERSION } from '../src/client';

const root = path.resolve(__dirname, '..');

function read(name: string): string {
	return fs.readFileSync(path.join(root, name), 'utf8');
}

describe('plugin package', () => {
	test('package.json is the Joplin plugin index package', () => {
		const pkg = JSON.parse(read('package.json'));
		expect(pkg.name).toBe('joplin-plugin-coworkingview');
		expect(pkg.license).toBe('MIT');
		expect(pkg.author).toBe('CoworkingView');
		expect(pkg.keywords).toContain('joplin-plugin');
		expect(pkg.version).toBe(PLUGIN_VERSION);
		expect(pkg.files).toEqual(['publish']);
		expect(pkg.scripts.dist).toContain('createArchive');
		expect(pkg.homepage).toBe('https://coworkingview.com');
	});

	test('manifest matches the published plugin id', () => {
		const manifest = JSON.parse(read('src/manifest.json'));
		expect(manifest.id).toBe('com.coworkingview.joplin');
		expect(manifest.author).toBe('CoworkingView');
		expect(manifest.homepage_url).toBe('https://coworkingview.com');
		expect(manifest.repository_url).toBe('https://github.com/coworkingview/flex-office-data');
		expect(manifest.version).toBe(PLUGIN_VERSION);
		expect(manifest.keywords).toContain('joplin-plugin');
	});

	test('commands use the labels Joplin shows in the command palette', () => {
		const source = read('src/index.ts');
		expect(source).toContain("const SEARCH_LABEL = 'CoworkingView: Insert workspace search results'");
		expect(source).toContain("const RATES_LABEL = 'CoworkingView: Insert market rates'");
		expect(source).toContain('label: SEARCH_LABEL');
		expect(source).toContain('label: RATES_LABEL');
	});
});

describe('README', () => {
	test('links to the site and the English path without tracking parameters', () => {
		const readme = read('README.md');
		expect(readme).toContain('](https://coworkingview.com)');
		expect(readme).toContain('](https://coworkingview.com/en)');
		expect(readme).not.toMatch(/utm_|donate|sponsor|buymeacoffee|github\.com\/sponsors/i);
		expect(readme).toContain('npm publish');
	});
});
