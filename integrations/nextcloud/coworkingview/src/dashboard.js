/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { createApp } from 'vue'
import WorkspaceWidget from './components/WorkspaceWidget.vue'

/**
 * Register the dashboard widget once the page can mount it.
 */
function register() {
	const dashboard = window.OCA?.Dashboard
	if (!dashboard || typeof dashboard.register !== 'function') {
		return
	}
	dashboard.register('coworkingview', (el) => {
		createApp(WorkspaceWidget, {
			preview: window.COWORKINGVIEW_PREVIEW ?? null,
		}).mount(el)
	})
}

if (document.readyState === 'loading') {
	document.addEventListener('DOMContentLoaded', register)
} else {
	register()
}
