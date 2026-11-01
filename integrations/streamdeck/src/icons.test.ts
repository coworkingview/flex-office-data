import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

const root = new URL("../com.coworkingview.prices.sdPlugin/", import.meta.url);

function pngSize(relativePath: string): { width: number; height: number } {
	const bytes = readFileSync(new URL(relativePath, root));
	assert.equal(bytes.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
	return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

describe("icons", () => {
	it("matches the manifest image sizes", () => {
		const expected: Record<string, [number, number]> = {
			"imgs/plugin/marketplace.png": [256, 256],
			"imgs/plugin/marketplace@2x.png": [512, 512],
			"imgs/plugin/category-icon.png": [28, 28],
			"imgs/plugin/category-icon@2x.png": [56, 56],
			"imgs/actions/workspace-count/icon.png": [20, 20],
			"imgs/actions/workspace-count/icon@2x.png": [40, 40],
			"imgs/actions/workspace-count/key.png": [72, 72],
			"imgs/actions/workspace-count/key@2x.png": [144, 144],
			"imgs/actions/market-rate/icon.png": [20, 20],
			"imgs/actions/market-rate/icon@2x.png": [40, 40],
			"imgs/actions/market-rate/key.png": [72, 72],
			"imgs/actions/market-rate/key@2x.png": [144, 144],
		};

		for (const [file, [width, height]] of Object.entries(expected)) {
			assert.deepEqual(pngSize(file), { width, height }, file);
		}
	});

	it("provides the separate 288 px Marketplace app icon", () => {
		const bytes = readFileSync(new URL("../marketplace/app-icon-288.png", import.meta.url));
		assert.equal(bytes.readUInt32BE(16), 288);
		assert.equal(bytes.readUInt32BE(20), 288);
	});

	it("provides a 1920 by 960 thumbnail and three gallery renderings", () => {
		for (const name of [
			"thumbnail.png",
			"gallery-keys.png",
			"gallery-workspace-count.png",
			"gallery-market-rate.png",
		]) {
			const bytes = readFileSync(new URL(`../marketplace/${name}`, import.meta.url));
			assert.equal(bytes.subarray(0, 8).toString("hex"), "89504e470d0a1a0a", name);
			assert.equal(bytes.readUInt32BE(16), 1920, name);
			assert.equal(bytes.readUInt32BE(20), 960, name);
		}
	});
});
