import properties from '../../fixtures/properties_berlin.json'
import { assertFixtureQuery } from '../../utils/assertFixtureQuery'

export default defineEventHandler((event) => {
  assertFixtureQuery(event)
  return properties
})
