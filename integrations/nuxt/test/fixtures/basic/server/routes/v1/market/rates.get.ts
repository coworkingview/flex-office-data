import rates from '../../../fixtures/market_rates_berlin_usd.json'
import { assertFixtureQuery } from '../../../utils/assertFixtureQuery'

export default defineEventHandler((event) => {
  assertFixtureQuery(event)
  return rates
})
