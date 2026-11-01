import { computed, toValue } from 'vue'
import { $fetch, useFetch, useRequestURL, useRuntimeConfig } from '#imports'
import type { MaybeRefOrGetter } from 'vue'
import type { UseFetchOptions } from '#app'
import { resolveBaseURL } from './base-url'
import { REQUEST_TIMEOUT_MS, RETRY_STATUS_CODES, USER_AGENT } from './constants'
import { retryDelayMs } from './http'
import type { CoworkingQueryValue } from './types'

type CoworkingFetchOptions<T> = Omit<UseFetchOptions<T>, 'baseURL' | 'query' | '$fetch' | 'transform'>

/**
 * `useFetch` against the public API through Nuxt's `$fetch`.
 * A relative `baseURL` (the test fixture uses `/`) is resolved on the current origin
 * so the request stays on that server.
 */
export function useCoworkingRequest<T>(
  path: '/v1/properties' | '/v1/market/rates',
  query: MaybeRefOrGetter<Record<string, CoworkingQueryValue>>,
  transform: (body: unknown) => T,
  options?: CoworkingFetchOptions<T>,
) {
  const config = useRuntimeConfig()
  const requestURL = useRequestURL()
  const baseURL = resolveBaseURL(config.public.coworkingview?.baseURL, requestURL.origin)
  const requestQuery = computed(() => toValue(query))

  const api = $fetch.create({
    baseURL,
    headers: {
      'Accept': 'application/json',
      'User-Agent': USER_AGENT,
    },
    timeout: REQUEST_TIMEOUT_MS,
    retry: 1,
    retryStatusCodes: [...RETRY_STATUS_CODES],
    retryDelay: context => retryDelayMs(context.response),
  })

  return useFetch(path, {
    ...options,
    $fetch: api,
    query: requestQuery,
    transform,
  } as UseFetchOptions<T>)
}
