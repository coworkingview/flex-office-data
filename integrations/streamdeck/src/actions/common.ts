import streamDeck, { type SendToPluginEvent, type WillAppearEvent } from "@elgato/streamdeck";

import { fetchCityOptions } from "../api.ts";
import { type ActionSettings, SITE_URL } from "../settings.ts";

export type KeyAction = WillAppearEvent<ActionSettings>["action"];

type PluginMessage = {
	event?: string;
};

/**
 * Opens the CoworkingView site. Used for a key press and the property inspector link.
 */
export async function openSite(): Promise<void> {
	await streamDeck.system.openUrl(SITE_URL);
}

/**
 * Fills the city dropdown from the published cities on `GET /v1/market/rates`.
 * If that request fails, the dropdown keeps Berlin, which is a real published city.
 */
export async function handlePropertyInspector(ev: SendToPluginEvent<PluginMessage, ActionSettings>): Promise<void> {
	const event = ev.payload?.event;
	if (event === "openSite") {
		await openSite();
		return;
	}
	if (event !== "getCities") {
		return;
	}

	try {
		const items = await fetchCityOptions();
		await streamDeck.ui.sendToPropertyInspector({
			event: "getCities",
			items: items.length > 0 ? items : [{ value: "berlin", label: "Berlin" }],
		});
	} catch (error) {
		streamDeck.logger.error("Unable to load CoworkingView cities", error);
		await streamDeck.ui.sendToPropertyInspector({
			event: "getCities",
			items: [{ value: "berlin", label: "Berlin" }],
		});
	}
}

export async function showUnavailable(action: KeyAction, alert: boolean): Promise<void> {
	if (!action.isKey()) {
		return;
	}
	await action.setTitle("—");
	if (alert) {
		await action.showAlert();
	}
}
