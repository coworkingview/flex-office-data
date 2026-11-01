import streamDeck, {
	action,
	type DidReceiveSettingsEvent,
	type KeyDownEvent,
	type SendToPluginEvent,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import { fetchWorkspaceCount } from "../api.ts";
import { type ActionSettings, cityOf, workspaceTitle } from "../settings.ts";
import { handlePropertyInspector, type KeyAction, openSite, showUnavailable } from "./common.ts";

/**
 * Shows how many coworking spaces are listed in a city.
 * The number is `meta.pagination.total` from `GET /v1/properties`.
 */
@action({ UUID: "com.coworkingview.prices.workspace-count" })
export class WorkspaceCountAction extends SingletonAction<ActionSettings> {
	private readonly visible = new Map<string, KeyAction>();

	/**
	 * Renders every visible Workspace Count key. Called on the 30 minute refresh.
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
		try {
			const count = await fetchWorkspaceCount(city);
			if (key.isKey()) {
				await key.setTitle(workspaceTitle(count.total, count.cityName));
			}
		} catch (error) {
			streamDeck.logger.error(`Workspace count failed for ${city}`, error);
			await showUnavailable(key, alert);
		}
	}
}
