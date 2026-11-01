import joplin from 'api';
import { MenuItemLocation, SettingItemType, ToastType } from 'api/types';

import { ApiError, CoworkingViewClient } from './client';
import {
	cityDialogHtml,
	formatListings,
	formatMarketRates,
	InputError,
	normalizeCity,
	resolveBaseUrl,
} from './format';

const SECTION = 'coworkingview';
const SETTING_CITY = 'defaultCity';
const SETTING_API_URL = 'apiUrl';

const SEARCH_LABEL = 'CoworkingView: Insert workspace search results';
const RATES_LABEL = 'CoworkingView: Insert market rates';

const SEARCH_PROMPT = 'City slug, for example berlin.';
const RATES_PROMPT = 'City slug, for example berlin. Leave this empty to insert rates for every published city.';

joplin.plugins.register({
	onStart: async function() {
		await joplin.settings.registerSection(SECTION, {
			label: 'CoworkingView',
			iconName: 'fas fa-building',
			description: 'Default city and optional API address for the CoworkingView commands.',
		});

		await joplin.settings.registerSettings({
			[SETTING_CITY]: {
				value: '',
				type: SettingItemType.String,
				section: SECTION,
				public: true,
				label: 'Default city',
				description: 'City slug used to pre-fill the commands, for example berlin. Leave empty to type a city each time.',
			},
			[SETTING_API_URL]: {
				value: '',
				type: SettingItemType.String,
				section: SECTION,
				public: true,
				label: 'API URL',
				description: 'Optional API root. Leave empty to use https://api.coworkingview.com.',
			},
		});

		const dialog = await joplin.views.dialogs.create('coworkingviewCityDialog');
		await joplin.views.dialogs.setButtons(dialog, [
			{ id: 'ok', title: 'Insert' },
			{ id: 'cancel', title: 'Cancel' },
		]);

		await joplin.commands.register({
			name: 'coworkingview.insertWorkspaceSearch',
			label: SEARCH_LABEL,
			execute: async () => {
				await runCommand(async (client, preset) => {
					const typed = await askCity(dialog, SEARCH_PROMPT, preset);
					if (typed === null) return;
					const city = normalizeCity(typed);
					const markdown = formatListings(await client.properties(city));
					if (!markdown) {
						await notify('No listings for that city.');
						return;
					}
					await insertMarkdown(markdown);
				});
			},
		});

		await joplin.commands.register({
			name: 'coworkingview.insertMarketRates',
			label: RATES_LABEL,
			execute: async () => {
				await runCommand(async (client, preset) => {
					const typed = await askCity(dialog, RATES_PROMPT, preset);
					if (typed === null) return;
					const city = typed.trim() ? normalizeCity(typed) : null;
					const markdown = formatMarketRates(await client.rates(city), city);
					if (!markdown) {
						await notify(city
							? 'The CoworkingView API did not return market rates for that city.'
							: 'The CoworkingView API did not return market rates.');
						return;
					}
					await insertMarkdown(markdown);
				});
			},
		});

		const info = await joplin.versionInfo();
		if (info.platform === 'desktop') {
			await joplin.views.menuItems.create(
				'coworkingview.insertWorkspaceSearchMenu',
				'coworkingview.insertWorkspaceSearch',
				MenuItemLocation.Tools,
			);
			await joplin.views.menuItems.create(
				'coworkingview.insertMarketRatesMenu',
				'coworkingview.insertMarketRates',
				MenuItemLocation.Tools,
			);
		}
	},
});

async function runCommand(
	action: (client: CoworkingViewClient, preset: string) => Promise<void>,
): Promise<void> {
	try {
		const settings = await joplin.settings.values([SETTING_CITY, SETTING_API_URL]);
		const preset = typeof settings[SETTING_CITY] === 'string' ? settings[SETTING_CITY] : '';
		const override = typeof settings[SETTING_API_URL] === 'string' ? settings[SETTING_API_URL] : '';
		const client = new CoworkingViewClient(resolveBaseUrl(override));
		await action(client, preset);
	} catch (error) {
		await notify(errorMessage(error));
	}
}

async function askCity(
	dialog: string,
	message: string,
	preset: string,
): Promise<string | null> {
	await joplin.views.dialogs.setHtml(dialog, cityDialogHtml(message, preset));
	const result = await joplin.views.dialogs.open(dialog);
	if (!result || (result.id !== 'ok' && result.id !== 'submit' && result.id !== 'yes' && result.id !== 'confirm')) {
		return null;
	}
	const form = result.formData && result.formData.coworkingview;
	const value = form ? form.city : '';
	if (typeof value === 'string') return value;
	if (Array.isArray(value) && typeof value[0] === 'string') return value[0];
	return '';
}

async function insertMarkdown(markdown: string): Promise<void> {
	const note = await joplin.workspace.selectedNote();
	if (!note) {
		await notify('Open a note, then run the command again.');
		return;
	}
	await joplin.commands.execute('insertText', `\n${markdown}\n`);
}

async function notify(message: string): Promise<void> {
	await joplin.views.dialogs.showToast({
		message: message.slice(0, 500),
		type: ToastType.Error,
	});
}

function errorMessage(error: unknown): string {
	if (error instanceof InputError || error instanceof ApiError || error instanceof Error) return error.message;
	return 'The CoworkingView request failed.';
}
