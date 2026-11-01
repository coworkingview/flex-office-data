import { addImports, createResolver, defineNuxtModule } from '@nuxt/kit'
import { COWORKINGVIEW_API_URL } from './runtime/constants'
import type { CoworkingPropertiesQuery, CoworkingPropertiesResponse, CoworkingProperty, CoworkingRateCity, CoworkingRatesData, CoworkingRatesQuery, CoworkingRatesResponse } from './runtime/types'

export type { CoworkingPropertiesQuery, CoworkingPropertiesResponse, CoworkingProperty, CoworkingRateCity, CoworkingRatesData, CoworkingRatesQuery, CoworkingRatesResponse }

export interface ModuleOptions {
  /**
   * API origin. No path and no API key.
   * Override with `COWORKINGVIEW_API_URL` when this is left at the default,
   * or at runtime with `NUXT_PUBLIC_COWORKINGVIEW_BASE_URL`.
   * @default 'https://api.coworkingview.com'
   */
  baseURL: string
  /**
   * Default `locale` query parameter (`en`, `es` or `de`).
   * @default 'en'
   */
  locale: 'en' | 'es' | 'de'
}

export default defineNuxtModule<ModuleOptions>({
  meta: {
    name: '@coworkingview/nuxt',
    configKey: 'coworkingview',
    compatibility: {
      nuxt: '>=3.0.0',
    },
  },
  defaults: {
    baseURL: COWORKINGVIEW_API_URL,
    locale: 'en',
  },
  setup(options, nuxt) {
    const resolver = createResolver(import.meta.url)
    const current = nuxt.options.runtimeConfig.public.coworkingview ?? {}

    nuxt.options.runtimeConfig.public.coworkingview = {
      baseURL: current.baseURL || resolveConfiguredBaseURL(options.baseURL),
      locale: current.locale || options.locale || 'en',
    }

    addImports([
      {
        name: 'useCoworkingProperties',
        from: resolver.resolve('./runtime/composables/useCoworkingProperties'),
      },
      {
        name: 'useCoworkingRates',
        from: resolver.resolve('./runtime/composables/useCoworkingRates'),
      },
    ])
  },
})

function resolveConfiguredBaseURL(configured: string | undefined): string {
  const env = process.env.COWORKINGVIEW_API_URL?.trim()
  if ((!configured || configured === COWORKINGVIEW_API_URL) && env && /^https?:\/\//i.test(env)) {
    return env.replace(/\/+$/, '')
  }
  if (!configured) {
    return COWORKINGVIEW_API_URL
  }
  if (configured === '/') {
    return configured
  }
  return configured.replace(/\/+$/, '')
}

declare module '@nuxt/schema' {
  interface PublicRuntimeConfig {
    coworkingview: {
      baseURL: string
      locale: 'en' | 'es' | 'de'
    }
  }
}

declare module 'nuxt/schema' {
  interface PublicRuntimeConfig {
    coworkingview: {
      baseURL: string
      locale: 'en' | 'es' | 'de'
    }
  }
}
