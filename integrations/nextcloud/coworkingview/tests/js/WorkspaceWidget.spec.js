/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import WorkspaceWidget from '../../src/components/WorkspaceWidget.vue'

const get = vi.fn()

vi.mock('@nextcloud/axios', () => ({
	default: {
		get: (...args) => get(...args),
	},
}))

vi.mock('@nextcloud/router', () => ({
	generateUrl: (url) => url,
}))

vi.mock('@nextcloud/l10n', () => ({
	translate: (_app, text, vars = {}) => text.replace(/\{(\w+)\}/g, (_, key) => String(vars[key] ?? `{${key}}`)),
}))

const cities = {
	cities: [
		{ slug: 'berlin', name: 'Berlin', countryCode: 'DE' },
		{ slug: 'madrid', name: 'Madrid', countryCode: 'ES' },
	],
	types: [
		{ code: 'private_office', label: 'Private office' },
		{ code: 'meeting_room', label: 'Meeting room' },
	],
}

const searchResult = {
	cityName: 'Berlin',
	typeLabel: 'Private office',
	workspaces: [
		{
			name: 'St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße',
			city: 'Berlin',
			typeLabel: 'Private office, Meeting room',
			url: 'https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin',
			description: 'This description must not be rendered',
			price: '214 EUR',
		},
	],
	total: 12,
	detailFailures: 0,
	citation: 'Source: CoworkingView — Coworking spaces in Berlin, https://coworkingview.com/en/coworking/berlin.',
	notice: 'You may link to listing pages.',
	moreUrl: 'https://coworkingview.com/en/coworking/berlin',
}

describe('WorkspaceWidget', () => {
	beforeEach(() => {
		get.mockReset()
		get.mockImplementation((url) => {
			if (url.endsWith('/api/cities')) {
				return Promise.resolve({ data: cities })
			}
			return Promise.resolve({ data: searchResult })
		})
	})

	it('searches by city and type and shows name, city, type and the listing link', async () => {
		const wrapper = mount(WorkspaceWidget)
		await flushPromises()

		expect(wrapper.text()).toContain('Berlin (DE)')
		expect(wrapper.get('button').attributes('disabled')).toBeDefined()

		await wrapper.get('select[name="city"]').setValue('berlin')
		await wrapper.get('select[name="type"]').setValue('private_office')
		await wrapper.get('form').trigger('submit')
		await flushPromises()

		expect(get).toHaveBeenCalledWith('/apps/coworkingview/api/workspaces', {
			params: { city: 'berlin', type: 'private_office' },
		})
		const link = wrapper.get('a.cwv__name')
		expect(link.text()).toBe('St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße')
		expect(link.attributes('href')).toBe('https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin')
		expect(wrapper.text()).toContain('Berlin')
		expect(wrapper.text()).toContain('Private office, Meeting room')
		expect(wrapper.text()).toContain('Showing 1 of 12.')
		expect(wrapper.text()).toContain('Source: CoworkingView')
		expect(wrapper.text()).not.toContain('This description must not be rendered')
		expect(wrapper.text()).not.toContain('214 EUR')
	})

	it('shows the empty state and an API error without inventing rows', async () => {
		get.mockImplementation((url) => {
			if (url.endsWith('/api/cities')) {
				return Promise.resolve({ data: cities })
			}
			return Promise.resolve({
				data: {
					workspaces: [],
					total: 0,
					detailFailures: 0,
					citation: null,
					notice: null,
					moreUrl: null,
				},
			})
		})
		const wrapper = mount(WorkspaceWidget)
		await flushPromises()
		await wrapper.get('select[name="city"]').setValue('madrid')
		await wrapper.get('form').trigger('submit')
		await flushPromises()
		expect(wrapper.text()).toContain('No workspaces matched this filter.')
		expect(wrapper.find('a.cwv__name').exists()).toBe(false)

		get.mockImplementation((url) => {
			if (url.endsWith('/api/cities')) {
				return Promise.resolve({ data: cities })
			}
			return Promise.reject({ response: { data: { message: 'Rate limit reached' } } })
		})
		const failed = mount(WorkspaceWidget)
		await flushPromises()
		await failed.get('select[name="city"]').setValue('berlin')
		await failed.get('form').trigger('submit')
		await flushPromises()
		expect(failed.text()).toContain('Rate limit reached')
		expect(failed.find('a.cwv__name').exists()).toBe(false)
	})
})
