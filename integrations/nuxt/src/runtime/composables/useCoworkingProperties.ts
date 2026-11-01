import { computed, toValue } from 'vue'
import { useRuntimeConfig } from '#imports'
import type { MaybeRefOrGetter } from 'vue'
import type { UseFetchOptions } from '#app'
import { buildPropertiesQuery } from '../query'
import { sanitizePropertiesResponse } from '../sanitize'
import type { CoworkingPropertiesQuery, CoworkingPropertiesResponse } from '../types'
import { useCoworkingRequest } from '../useCoworkingRequest'

/**
 * One page of `GET /v1/properties`.
 *
 * ```vue
 * <script setup lang="ts">
 * const { data } = await useCoworkingProperties({ city: 'berlin' })
 * </script>
 * ```
 *
 * `data.meta.citation` and `data.meta.catalogueNotice` are kept.
 * Photos, logos and description text are not.
 */
export function useCoworkingProperties(
  query?: MaybeRefOrGetter<CoworkingPropertiesQuery>,
  options?: Omit<UseFetchOptions<CoworkingPropertiesResponse>, 'baseURL' | 'query' | '$fetch' | 'transform'>,
) {
  const config = useRuntimeConfig()
  const requestQuery = computed(() => buildPropertiesQuery(
    config.public.coworkingview?.locale,
    toValue(query),
  ))
  return useCoworkingRequest('/v1/properties', requestQuery, sanitizePropertiesResponse, options)
}
