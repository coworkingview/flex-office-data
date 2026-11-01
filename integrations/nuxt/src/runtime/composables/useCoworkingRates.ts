import { computed, toValue } from 'vue'
import { useRuntimeConfig } from '#imports'
import type { MaybeRefOrGetter } from 'vue'
import type { UseFetchOptions } from '#app'
import { buildRatesQuery } from '../query'
import { sanitizeRatesResponse } from '../sanitize'
import type { CoworkingRatesQuery, CoworkingRatesResponse } from '../types'
import { useCoworkingRequest } from '../useCoworkingRequest'

/**
 * `GET /v1/market/rates` (CoworkingView Price Index, CC BY 4.0).
 *
 * ```vue
 * <script setup lang="ts">
 * const { data } = await useCoworkingRates({ city: 'berlin' })
 * </script>
 * ```
 *
 * `const { data } = await useCoworkingRates(...)` — `data` is the envelope
 * `{ data, meta }`. Keep `data.data.attribution` with anything you publish,
 * together with `data.data.license` and `data.data.licenseUrl`.
 */
export function useCoworkingRates(
  query?: MaybeRefOrGetter<CoworkingRatesQuery>,
  options?: Omit<UseFetchOptions<CoworkingRatesResponse>, 'baseURL' | 'query' | '$fetch' | 'transform'>,
) {
  const config = useRuntimeConfig()
  const requestQuery = computed(() => buildRatesQuery(
    config.public.coworkingview?.locale,
    toValue(query),
  ))
  return useCoworkingRequest('/v1/market/rates', requestQuery, sanitizeRatesResponse, options)
}
