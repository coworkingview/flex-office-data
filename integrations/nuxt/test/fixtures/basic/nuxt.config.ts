import CoworkingView from '../../../src/module'

export default defineNuxtConfig({
  modules: [
    CoworkingView,
  ],
  devtools: { enabled: false },
  compatibilityDate: '2026-11-01',
  coworkingview: {
    baseURL: '/',
  },
})
