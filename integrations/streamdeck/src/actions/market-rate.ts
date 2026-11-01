import streamDeck, {
	action,
	type DidReceiveSettingsEvent,
	type KeyDownEvent,
	type SendToPluginEvent,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import { fetchMarketRate } from "../api.ts";
import { type ActionSettings, cityOf, figureOf, rateTitle } from "../settings.ts";
import { handlePropertyInspector, type KeyAction, openSite, showUnavailable } from "./common.ts";

/**
 * Shows one Price Index median from `GET /v1/market/rates` for the chosen city.
 */
@action({ UUID: "com.coworkingview.prices.market-rate" })
export class MarketRateAction extends SingletonAction<ActionSettings> {
	private readonly visible = new Map<string, KeyAction>();

	/**
	 * Renders every visible Market Rate key. Called on the 30 minute refresh.
	 */
	public async refreshAll(): Promise<void> {
		await Promise.all(
			[...this.visible.values()].map(async (key) => {
				const settings = await key.getSettings();
				await this.render(key, settings, false);
			}),
		);
	}

	override async onWillAppear(ev: WillAppearEvent<ActionSettings>): Promise<void> {
		this.visible.set(ev.action.id, ev.action);
		await this.render(ev.action, ev.payload.settings, true);
	}

	override onWillDisappear(ev: WillDisappearEvent<ActionSettings>): void {
		this.visible.delete(ev.action.id);
	}

	override async onKeyDown(_ev: KeyDownEvent<ActionSettings>): Promise<void> {
		await openSite();
	}

	override async onDidReceiveSettings(ev: DidReceiveSettingsEvent<ActionSettings>): Promise<void> {
		await this.render(ev.action, ev.payload.settings, true);
	}

	override async onSendToPlugin(ev: SendToPluginEvent<{ event?: string }, ActionSettings>): Promise<void> {
		await handlePropertyInspector(ev);
	}

	private async render(key: KeyAction, settings: ActionSettings, alert: boolean): Promise<void> {
		const city = cityOf(settings);
		const figure = figureOf(settings);
		try {
			const rate = await fetchMarketRate(city, figure);
			if (!rate) {
				streamDeck.logger.warn(`No ${figure} median for ${city}`);
				await showUnavailable(key, alert);
				return;
			}
			if (key.isKey()) {
				await key.setTitle(rateTitle(rate.amount, rate.currency, rate.label, rate.cityName));
			}
		} catch (error) {
			streamDeck.logger.error(`Market rate failed for ${city}`, error);
			await showUnavailable(key, alert);
		}
	}
}
