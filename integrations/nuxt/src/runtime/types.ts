export interface CoworkingMoney {
  amount: number
  currency: string
}

export interface CoworkingCityRef {
  slug: string
  name: string
}

/**
 * One listing from `GET /v1/properties`.
 * Photos, logos and description text are removed before this object is returned.
 */
export interface CoworkingProperty {
  slug: string
  title: string
  countryCode?: string
  city?: CoworkingCityRef
  zone?: CoworkingCityRef | null
  operator?: {
    slug?: string
    name?: string
  }
  coordinates?: {
    lat: number
    lng: number
  }
  fromPrice?: CoworkingMoney
  fromBillingPeriod?: string
  featured?: boolean
  updatedAt?: string
  amenities?: string[]
  capacity?: number
  marketPosition?: {
    verdict?: 'below' | 'around' | 'above'
    median?: CoworkingMoney
    sampleSize?: number
  }
}

export interface CoworkingCitation {
  source?: string
  title?: string
  url?: string
  accessed?: string
  text?: string
}

export interface CoworkingPagination {
  page: number
  pageSize: number
  total: number
  pageCount: number
}

export interface CoworkingPropertiesMeta {
  contractVersion?: string
  pagination?: CoworkingPagination
  seed?: number
  citation?: CoworkingCitation
  catalogueNotice?: string
}

export interface CoworkingPropertiesResponse {
  data: CoworkingProperty[]
  meta: CoworkingPropertiesMeta
}

/** Query string of `GET /v1/properties`. Names are the API's. */
export interface CoworkingPropertiesQuery {
  locale?: 'en' | 'es' | 'de'
  city?: string
  country?: string
  zone?: string
  operator?: string
  pricingOptionType?: string
  minCapacity?: number
  minPrice?: number
  maxPrice?: number
  currency?: 'EUR' | 'GBP' | 'USD' | 'CHF' | 'AED'
  sortBy?: 'random' | 'price-asc' | 'date-desc' | 'date-asc'
  page?: number
  pageSize?: number
  seed?: number
}

export interface CoworkingRateStat {
  optionType?: string
  median?: CoworkingMoney
  p25?: CoworkingMoney | null
  p75?: CoworkingMoney | null
  min?: CoworkingMoney
  max?: CoworkingMoney
  sampleSize?: number
  propertyCount?: number
  operatorCount?: number
  insufficientData?: boolean
}

export interface CoworkingRateBuilding {
  price?: CoworkingMoney
  name?: string
  slug?: string
  operatorName?: string
  operatorSlug?: string
}

/** One city object inside `GET /v1/market/rates` `data.cities`. */
export interface CoworkingRateCity {
  city?: CoworkingCityRef
  countryCode?: string
  currency?: string
  byType?: CoworkingRateStat[]
  figures?: CoworkingRateStat[]
  dayPass?: CoworkingRateStat
  meetingRoom?: CoworkingRateStat
  propertyCount?: number
  operatorCount?: number
  insufficientData?: boolean
  p25?: CoworkingMoney | null
  p75?: CoworkingMoney | null
  min?: CoworkingMoney
  max?: CoworkingMoney
  entryMedian?: CoworkingMoney
  entryMin?: CoworkingMoney
  entryMax?: CoworkingMoney
  buildings?: CoworkingRateBuilding[]
  sampleSize?: number
}

export interface CoworkingUnpublishedCity {
  city?: CoworkingCityRef
  insufficientData?: boolean
}

/**
 * `data` of `GET /v1/market/rates`.
 * `attribution`, `license` and `licenseUrl` travel with the Price Index (CC BY 4.0).
 */
export interface CoworkingRatesData {
  cities?: CoworkingRateCity[]
  unpublished?: CoworkingUnpublishedCity[]
  totalProperties?: number
  totalPricePoints?: number
  asOf?: string
  license?: string
  licenseUrl?: string
  attribution?: string
  scope?: string
  copyright?: string
}

export interface CoworkingRatesResponse {
  data: CoworkingRatesData
  meta?: {
    contractVersion?: string
  }
}

/** Query string of `GET /v1/market/rates`. Names are the API's. */
export interface CoworkingRatesQuery {
  locale?: 'en' | 'es' | 'de'
  city?: string
  country?: string
  currency?: 'EUR' | 'GBP' | 'USD' | 'CHF' | 'AED'
}

export type CoworkingQueryValue = string | number
