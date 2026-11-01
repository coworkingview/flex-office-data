import type { H3Event } from 'h3'

/** The fixture server only answers the query the composables are supposed to send. */
export function assertFixtureQuery(event: H3Event) {
  const query = getQuery(event)
  if (query.city !== 'berlin' || query.locale !== 'en') {
    throw createError({
      statusCode: 400,
      statusMessage: `unexpected query ${JSON.stringify(query)}`,
    })
  }
  const accept = getRequestHeader(event, 'accept')
  if (!accept?.includes('application/json')) {
    throw createError({
      statusCode: 400,
      statusMessage: `unexpected accept ${accept ?? ''}`,
    })
  }
}
