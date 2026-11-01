# CoworkingView

[![npm version][npm-version-src]][npm-version-href]
[![npm downloads][npm-downloads-src]][npm-downloads-href]
[![License][license-src]][license-href]
[![Nuxt][nuxt-src]][nuxt-href]

Coworking listings and [Price Index](https://coworkingview.com/en/tools/price-index) rates from the public [CoworkingView](https://coworkingview.com) API (`https://api.coworkingview.com`). No API key.

- [✨ &nbsp;Release Notes](/CHANGELOG.md)
<!-- - [🏀 Online playground](https://stackblitz.com/github/coworkingview/flex-office-data?file=integrations/nuxt/playground/app.vue) -->
<!-- - [📖 &nbsp;Documentation](https://coworkingview.com) -->

## Features

<!-- Highlight some of the features your module provide here -->
- ⛰ &nbsp;`useCoworkingProperties` — `GET /v1/properties`
- 🚠 &nbsp;`useCoworkingRates` — `GET /v1/market/rates`
- 🌲 &nbsp;Auto-imported composables, typed responses, `useFetch` / `$fetch`

## Quick Setup

Install the module to your Nuxt application with one command:

```bash
npx nuxi module add @coworkingview/nuxt
```

That's it! You can now use CoworkingView in your Nuxt app ✨

```ts
export default defineNuxtConfig({
  modules: ['@coworkingview/nuxt'],
  coworkingview: {
    // baseURL: 'https://api.coworkingview.com',
    // locale: 'en', // en | es | de
  },
})
```

`COWORKINGVIEW_API_URL` overrides the default origin when `baseURL` is left unset. `NUXT_PUBLIC_COWORKINGVIEW_BASE_URL` overrides it at runtime.

```vue
<script setup lang="ts">
const { data: properties } = await useCoworkingProperties({ city: 'berlin' })
const { data: rates } = await useCoworkingRates({ city: 'berlin' })
</script>

<template>
  <p>{{ rates?.data?.attribution }}</p>
  <ul>
    <li v-for="space in properties?.data ?? []" :key="space.slug">
      {{ space.title }}
    </li>
  </ul>
</template>
```

`useCoworkingProperties` accepts the `GET /v1/properties` query: `locale`, `city`, `country`, `zone`, `operator`, `pricingOptionType`, `minCapacity`, `minPrice`, `maxPrice`, `currency`, `sortBy`, `page`, `pageSize`, `seed`. `pageSize` is capped at 50. One call is one page.

`useCoworkingRates` accepts the `GET /v1/market/rates` query: `locale`, `city`, `country`, `currency`.

Photos, logos and description text are removed from listings. `meta.citation` and `meta.catalogueNotice` stay on the properties response. The catalogue notice says descriptions, images, logos, names and prices belong to the operators and that systematic extraction is not permitted.

## Attribution

The Price Index is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). `useFetch`'s `data` is the API envelope. Attribution is `data.data.attribution`, with `data.data.license` (`CC-BY-4.0`) and `data.data.licenseUrl`. Keep that attribution next to any figure you publish. One response reads:

> Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index), as of October 2026. Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Aggregated figures only; no endorsement by CoworkingView or any operator is implied.

The date follows `data.asOf`. Credit [CoworkingView](https://coworkingview.com).

## Contribution

<details>
  <summary>Local development</summary>

  ```bash
  # Install dependencies
  npm install

  # Generate type stubs
  npm run dev:prepare

  # Develop with the playground
  npm run dev

  # Build the playground
  npm run dev:build

  # Run ESLint
  npm run lint

  # Run Vitest
  npm run test
  npm run test:watch

  # Release new version
  npm run release
  ```

</details>

This module was built with AI assistance.

<!-- Badges -->
[npm-version-src]: https://img.shields.io/npm/v/@coworkingview/nuxt/latest.svg?style=flat&colorA=020420&colorB=00DC82
[npm-version-href]: https://npmjs.com/package/@coworkingview/nuxt

[npm-downloads-src]: https://img.shields.io/npm/dm/@coworkingview/nuxt.svg?style=flat&colorA=020420&colorB=00DC82
[npm-downloads-href]: https://npm.chart.dev/@coworkingview/nuxt

[license-src]: https://img.shields.io/npm/l/@coworkingview/nuxt.svg?style=flat&colorA=020420&colorB=00DC82
[license-href]: https://npmjs.com/package/@coworkingview/nuxt

[nuxt-src]: https://img.shields.io/badge/Nuxt-020420?logo=nuxt
[nuxt-href]: https://nuxt.com
