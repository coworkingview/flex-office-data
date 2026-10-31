<!--
  - SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

<template>
	<div class="cwv">
		<form class="cwv__form" @submit.prevent="search">
			<label class="cwv__field">
				<span>{{ t('coworkingview', 'City') }}</span>
				<select
					v-model="city"
					name="city"
					:disabled="loadingCities || searching"
					required>
					<option disabled value="">
						{{ t('coworkingview', 'Choose a city') }}
					</option>
					<option
						v-for="item in cities"
						:key="item.slug"
						:value="item.slug">
						{{ cityOption(item) }}
					</option>
				</select>
			</label>
			<label class="cwv__field">
				<span>{{ t('coworkingview', 'Workspace type') }}</span>
				<select
					v-model="type"
					name="type"
					:disabled="loadingCities || searching">
					<option value="">
						{{ t('coworkingview', 'All types') }}
					</option>
					<option
						v-for="item in types"
						:key="item.code"
						:value="item.code">
						{{ item.label }}
					</option>
				</select>
			</label>
			<button
				class="primary"
				type="submit"
				:disabled="!city || searching || loadingCities">
				{{ searching ? t('coworkingview', 'Searching…') : t('coworkingview', 'Search') }}
			</button>
		</form>

		<p v-if="loadingCities" class="cwv__status">
			{{ t('coworkingview', 'Loading cities…') }}
		</p>
		<p v-else-if="citiesError" class="cwv__error" role="alert">
			{{ citiesError }}
		</p>
		<p v-else-if="!result && !searchError" class="cwv__hint">
			{{ t('coworkingview', 'Choose a city and a workspace type. Search sends that choice to the public CoworkingView API. Results show the name, city, type and a link to the listing. Prices, photos and descriptions are not stored.') }}
		</p>

		<p v-if="searchError" class="cwv__error" role="alert">
			{{ searchError }}
		</p>

		<ul v-if="result && result.workspaces.length" class="cwv__list">
			<li v-for="space in result.workspaces" :key="space.url" class="cwv__item">
				<a
					class="cwv__name"
					:href="space.url"
					target="_blank"
					rel="noopener noreferrer">{{ space.name }}</a>
				<p class="cwv__meta">
					<span class="cwv__city">{{ space.city }}</span>
					<span v-if="space.typeLabel" class="cwv__type">{{ space.typeLabel }}</span>
				</p>
			</li>
		</ul>
		<p v-else-if="result" class="cwv__status">
			{{ t('coworkingview', 'No workspaces matched this filter.') }}
		</p>

		<p v-if="moreLine" class="cwv__more">
			<span>{{ moreLine }}</span>
			<a
				v-if="result.moreUrl"
				:href="result.moreUrl"
				target="_blank"
				rel="noopener noreferrer">{{ t('coworkingview', 'More on CoworkingView') }}</a>
		</p>
		<p v-if="result && result.detailFailures > 0" class="cwv__hint">
			{{ failureLine }}
		</p>
		<footer v-if="result && (result.citation || result.notice)" class="cwv__cite">
			<p v-if="result.citation">
				{{ result.citation }}
			</p>
			<p v-if="result.notice">
				{{ result.notice }}
			</p>
		</footer>
	</div>
</template>

<script setup>
import axios from '@nextcloud/axios'
import { translate as t } from '@nextcloud/l10n'
import { generateUrl } from '@nextcloud/router'
import { computed, onMounted, ref } from 'vue'

const props = defineProps({
	preview: {
		type: Object,
		default: null,
	},
})

const cities = ref([])
const types = ref([])
const city = ref('')
const type = ref('')
const loadingCities = ref(false)
const searching = ref(false)
const citiesError = ref('')
const searchError = ref('')
const result = ref(null)

const moreLine = computed(() => {
	if (!result.value || result.value.total === null || result.value.total === undefined) {
		return ''
	}
	const shown = result.value.workspaces.length
	const total = result.value.total
	if (total <= shown) {
		return ''
	}
	return t('coworkingview', 'Showing {shown} of {total}.', { shown, total })
})

const failureLine = computed(() => {
	if (!result.value) {
		return ''
	}
	return t('coworkingview', 'Workspace type could not be read for {count} listings.', {
		count: result.value.detailFailures,
	})
})

/**
 * City label, with the country code when the API sent one.
 *
 * @param {object} item City row from the app API.
 * @param {string} item.name City name.
 * @param {string|null} [item.countryCode] ISO country code.
 * @return {string} Label shown in the city menu.
 */
function cityOption(item) {
	if (item.countryCode) {
		return t('coworkingview', '{name} ({code})', { name: item.name, code: item.countryCode })
	}
	return item.name
}

/**
 * Prefer the message from the app proxy when it sent one.
 *
 * @param {Error & { response?: { data?: { message?: string } } }} error Failed request.
 * @param {string} fallback Text used when the response has no message.
 * @return {string} Message to show.
 */
function messageFrom(error, fallback) {
	const message = error?.response?.data?.message
	return typeof message === 'string' && message !== '' ? message : fallback
}

/**
 * Load the city and workspace-type lists.
 *
 * @return {Promise<void>}
 */
async function loadCities() {
	loadingCities.value = true
	citiesError.value = ''
	try {
		const response = await axios.get(generateUrl('/apps/coworkingview/api/cities'))
		cities.value = response.data.cities ?? []
		types.value = response.data.types ?? []
	} catch (error) {
		citiesError.value = messageFrom(error, t('coworkingview', 'The city list could not be loaded.'))
	} finally {
		loadingCities.value = false
	}
}

/**
 * Search the selected city and workspace type.
 *
 * @return {Promise<void>}
 */
async function search() {
	if (!city.value || searching.value) {
		return
	}
	searching.value = true
	searchError.value = ''
	try {
		const response = await axios.get(generateUrl('/apps/coworkingview/api/workspaces'), {
			params: {
				city: city.value,
				type: type.value,
			},
		})
		result.value = response.data
	} catch (error) {
		result.value = null
		searchError.value = messageFrom(error, t('coworkingview', 'The search could not be completed.'))
	} finally {
		searching.value = false
	}
}

onMounted(() => {
	if (props.preview) {
		cities.value = props.preview.cities ?? []
		types.value = props.preview.types ?? []
		city.value = props.preview.city ?? ''
		type.value = props.preview.type ?? ''
		result.value = props.preview.result ?? null
		return
	}
	loadCities()
})
</script>

<style scoped>
.cwv {
	display: flex;
	flex-direction: column;
	gap: 12px;
	padding: 4px 2px 8px;
	color: var(--color-main-text);
}

.cwv__form {
	display: flex;
	flex-wrap: wrap;
	gap: 8px;
	align-items: end;
}

.cwv__field {
	display: flex;
	flex: 1 1 140px;
	flex-direction: column;
	gap: 4px;
	min-width: 0;
	font-size: var(--font-size-small, 13px);
	color: var(--color-text-maxcontrast);
}

.cwv select,
.cwv button {
	font: inherit;
	color: var(--color-main-text);
}

.cwv select {
	width: 100%;
	min-height: 34px;
	padding: 4px 8px;
	border: 1px solid var(--color-border);
	border-radius: var(--border-radius, 8px);
	background: var(--color-main-background);
}

.cwv button {
	min-height: 34px;
	padding: 6px 14px;
	border: 0;
	border-radius: var(--border-radius-pill, 100px);
	background: var(--color-primary-element, #006aa3);
	color: var(--color-primary-element-text, #fff);
	cursor: pointer;
}

.cwv button:disabled {
	opacity: 0.6;
	cursor: default;
}

.cwv__hint,
.cwv__status,
.cwv__cite {
	margin: 0;
	color: var(--color-text-maxcontrast);
	font-size: var(--font-size-small, 13px);
	line-height: 1.4;
}

.cwv__error {
	margin: 0;
	color: var(--color-error, #c70000);
	font-size: var(--font-size-small, 13px);
}

.cwv__list {
	list-style: none;
	margin: 0;
	padding: 0;
}

.cwv__item {
	padding: 8px 0;
	border-bottom: 1px solid var(--color-border);
}

.cwv__item:last-child {
	border-bottom: 0;
}

.cwv__name {
	font-weight: 600;
	text-decoration: none;
}

.cwv__name:hover,
.cwv__name:focus {
	text-decoration: underline;
}

.cwv__meta {
	display: flex;
	flex-wrap: wrap;
	gap: 8px;
	margin: 2px 0 0;
	color: var(--color-text-maxcontrast);
	font-size: var(--font-size-small, 13px);
}

.cwv__type::before {
	content: '·';
	margin-inline-end: 8px;
}

.cwv__more {
	display: flex;
	flex-wrap: wrap;
	gap: 8px;
	margin: 0;
	font-size: var(--font-size-small, 13px);
}

.cwv__cite p {
	margin: 0 0 6px;
}
</style>
