import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { parseCityOptions, parseMarketRate, parseWorkspaceCount } from "./parse.ts";
import {
	cityOf,
	DEFAULT_CITY,
	figureOf,
	rateTitle,
	REFRESH_INTERVAL_MS,
	SITE_URL,
	workspaceTitle,
} from "./settings.ts";

const ratesBerlin = JSON.parse(readFileSync(new URL("../fixtures/rates-berlin.json", import.meta.url), "utf8"));
const ratesCities = JSON.parse(readFileSync(new URL("../fixtures/rates-cities.json", import.meta.url), "utf8"));
const propertiesBerlin = JSON.parse(
	readFileSync(new URL("../fixtures/properties-berlin.json", import.meta.url), "utf8"),
);

describe("settings", () => {
	it("opens the canonical site and refreshes every 30 minutes", () => {
		assert.equal(SITE_URL, "https://coworkingview.com");
		assert.equal(REFRESH_INTERVAL_MS, 1_800_000);
		assert.equal(DEFAULT_CITY, "berlin");
	});

	it("defaults a missing or invalid city to berlin", () => {
		assert.equal(cityOf({}), "berlin");
		assert.equal(cityOf({ city: "Madrid" }), "madrid");
		assert.equal(cityOf({ city: "../etc" }), "berlin");
	});

	it("defaults an unknown figure to the flex desk median", () => {
		assert.equal(figureOf({}), "flex_desk");
		assert.equal(figureOf({ figure: "day_pass" }), "day_pass");
		assert.equal(figureOf({ figure: "hot_desk" }), "flex_desk");
	});
});

describe("workspace count", () => {
	it("reads the catalogue total and the listing city name", () => {
		const count = parseWorkspaceCount(propertiesBerlin, "berlin");
		assert.ok(count);
		assert.equal(count.total, propertiesBerlin.meta.pagination.total);
		assert.equal(count.cityName, "Berlin");
		assert.match(count.citation ?? "", /CoworkingView/);
		assert.equal(workspaceTitle(count.total, count.cityName), `${count.total}\nBerlin`);
	});

	it("ignores operator prose when a listing includes it", () => {
		const withProse = {
			data: [
				{
					slug: "example",
					title: "Operator title that must not be shown",
					excerpt: "Operator description that must not be shown",
					images: [{ url: "https://example.com/photo.webp" }],
					city: { slug: "berlin", name: "Berlin" },
				},
			],
			meta: { pagination: { total: 4 } },
		};
		const count = parseWorkspaceCount(withProse, "berlin");
		assert.deepEqual(count, { total: 4, cityName: "Berlin", citation: null });
		assert.equal(JSON.stringify(count).includes("Operator"), false);
	});

	it("keeps the slug when the page has no listing", () => {
		const count = parseWorkspaceCount({ data: [], meta: { pagination: { total: 0 } } }, "augsburg");
		assert.deepEqual(count, { total: 0, cityName: "augsburg", citation: null });
	});
});

describe("market rate", () => {
	it("reads the flex desk monthly median for Berlin", () => {
		const flex = ratesBerlin.data.cities[0].figures.find(
			(figure: { optionType: string }) => figure.optionType === "flex_desk",
		);
		const rate = parseMarketRate(ratesBerlin, "berlin", "flex_desk");
		assert.ok(rate);
		assert.equal(rate.cityName, "Berlin");
		assert.equal(rate.amount, flex.median.amount);
		assert.equal(rate.currency, flex.median.currency);
		assert.equal(rate.label, "Flex desk");
		assert.equal(rate.unit, "month");
		assert.equal(rate.sampleSize, flex.sampleSize);
		assert.equal(rate.asOf, ratesBerlin.data.asOf);
		assert.equal(rate.attribution, ratesBerlin.data.attribution);
		assert.match(rate.attribution ?? "", /CC BY 4.0/);
		assert.equal(
			rateTitle(rate.amount, rate.currency, rate.label, rate.cityName),
			`${flex.median.amount} ${flex.median.currency}\nFlex desk\nBerlin`,
		);
	});

	it("reads the day pass and meeting room objects", () => {
		const city = ratesBerlin.data.cities[0];
		const dayPass = parseMarketRate(ratesBerlin, "berlin", "day_pass");
		const meetingRoom = parseMarketRate(ratesBerlin, "berlin", "meeting_room");
		assert.equal(dayPass?.amount, city.dayPass.median.amount);
		assert.equal(dayPass?.currency, city.dayPass.median.currency);
		assert.equal(dayPass?.unit, "day");
		assert.equal(meetingRoom?.amount, city.meetingRoom.median.amount);
		assert.equal(meetingRoom?.currency, city.meetingRoom.median.currency);
		assert.equal(meetingRoom?.unit, "hour");
	});

	it("returns null when the city or figure is missing", () => {
		assert.equal(parseMarketRate(ratesBerlin, "no-such-city", "flex_desk"), null);
		const withoutFlex = structuredClone(ratesBerlin);
		withoutFlex.data.cities[0].figures = withoutFlex.data.cities[0].figures.filter(
			(figure: { optionType: string }) => figure.optionType !== "flex_desk",
		);
		assert.equal(parseMarketRate(withoutFlex, "berlin", "flex_desk"), null);
	});
});

describe("cities", () => {
	it("lists published cities by name", () => {
		const options = parseCityOptions(ratesCities);
		assert.deepEqual(
			options.map((option) => option.value),
			["amsterdam", "berlin", "madrid"],
		);
		assert.deepEqual(
			options.map((option) => option.label),
			["Amsterdam", "Berlin", "Madrid"],
		);
	});
});
