-- CoworkingView Price Index snapshot for PostgreSQL.
-- Rows copied from spec/golden/rates.csv and spec/golden/cities.csv, which
-- are generated from spec/fixtures/market_rates.json (recorded
-- GET /v1/market/rates). Attribution, licence and scope are the fixture's
-- own fields. Regenerate with tools/build_sql.py. Do not type prices in.

CREATE TABLE coworkingview_about (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    as_of timestamptz NOT NULL,
    attribution text NOT NULL,
    license text NOT NULL,
    license_url text NOT NULL,
    scope text NOT NULL
);

COMMENT ON TABLE coworkingview_about IS
    'Licence and attribution for the embedded CoworkingView Price Index snapshot';

CREATE TABLE coworkingview_price_index (
    city_slug text NOT NULL,
    city_name text NOT NULL,
    country_code text,
    currency text NOT NULL,
    product text NOT NULL,
    unit text,
    median numeric NOT NULL,
    p25 numeric,
    p75 numeric,
    sample_size integer NOT NULL,
    property_count integer,
    operator_count integer,
    low_confidence boolean NOT NULL,
    as_of timestamptz NOT NULL,
    PRIMARY KEY (city_slug, product)
);

COMMENT ON TABLE coworkingview_price_index IS
    'Snapshot of the CoworkingView Price Index, one row per city and product (CC BY 4.0)';

CREATE TABLE coworkingview_cities (
    city_slug text PRIMARY KEY,
    city_name text NOT NULL,
    country_code text,
    currency text,
    published boolean NOT NULL,
    property_count integer,
    operator_count integer,
    entry_median numeric,
    entry_min numeric,
    entry_max numeric,
    p25 numeric,
    p75 numeric,
    sample_size integer,
    as_of timestamptz NOT NULL
);

COMMENT ON TABLE coworkingview_cities IS
    'Snapshot of CoworkingView Price Index cities, including unpublished cities (CC BY 4.0)';

INSERT INTO coworkingview_about (
    singleton, as_of, attribution, license, license_url, scope
) VALUES (
    true,
    '2026-10-27T21:06:48.313Z',
    'Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index), as of October 2026. Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Aggregated figures only; no endorsement by CoworkingView or any operator is implied.',
    'CC-BY-4.0',
    'https://creativecommons.org/licenses/by/4.0/',
    'This licence covers the CoworkingView Price Index and catalogue data in this dataset: prices and price statistics, space and operator names, and descriptions written by CoworkingView. It does not cover, and this dataset does not contain: photos, logos, reviews or ratings, data obtained from Google, or any other content of coworkingview.com, its API or MCP server, which remain subject to their own terms. Names are included for identification only; no trademark rights in CoworkingView or operator names and marks are licensed.'
);

INSERT INTO coworkingview_price_index (city_slug, city_name, country_code, currency, product, unit, median, p25, p75, sample_size, property_count, operator_count, low_confidence, as_of) VALUES
    ('abu-dhabi', 'Abu Dhabi', 'AE', 'AED', 'flex_desk', 'month', 1400, 1400, 1800, 3, 2, 1, true, '2026-10-27T21:06:48.313Z'),
    ('abu-dhabi', 'Abu Dhabi', 'AE', 'AED', 'fix_desk', 'month', 1800, 1800, 1800, 2, 2, 1, true, '2026-10-27T21:06:48.313Z'),
    ('abu-dhabi', 'Abu Dhabi', 'AE', 'AED', 'private_office', 'month', 2057, 1486, 2629, 2, 2, 1, true, '2026-10-27T21:06:48.313Z'),
    ('berlin', 'Berlin', 'DE', 'EUR', 'flex_desk', 'month', 214, 199, 292, 72, 66, 38, false, '2026-10-27T21:06:48.313Z'),
    ('berlin', 'Berlin', 'DE', 'EUR', 'fix_desk', 'month', 310, 290, 421, 60, 56, 37, false, '2026-10-27T21:06:48.313Z'),
    ('berlin', 'Berlin', 'DE', 'EUR', 'private_office', 'month', 480, 399, 550, 59, 38, 20, false, '2026-10-27T21:06:48.313Z'),
    ('berlin', 'Berlin', 'DE', 'EUR', 'day_pass', 'day', 35, NULL, NULL, 59, 55, 27, false, '2026-10-27T21:06:48.313Z'),
    ('berlin', 'Berlin', 'DE', 'EUR', 'meeting_room', 'hour', 32, NULL, NULL, 79, 51, 25, false, '2026-10-27T21:06:48.313Z'),
    ('madrid', 'Madrid', 'ES', 'EUR', 'flex_desk', 'month', 175, 130, 199, 13, 6, 4, false, '2026-10-27T21:06:48.313Z'),
    ('madrid', 'Madrid', 'ES', 'EUR', 'fix_desk', 'month', 260, 249, 280, 9, 7, 5, true, '2026-10-27T21:06:48.313Z'),
    ('madrid', 'Madrid', 'ES', 'EUR', 'private_office', 'month', 385, 275, 449, 9, 7, 3, true, '2026-10-27T21:06:48.313Z'),
    ('madrid', 'Madrid', 'ES', 'EUR', 'day_pass', 'day', 22, NULL, NULL, 11, 7, 4, false, '2026-10-27T21:06:48.313Z'),
    ('madrid', 'Madrid', 'ES', 'EUR', 'meeting_room', 'hour', 28, NULL, NULL, 8, 6, 3, true, '2026-10-27T21:06:48.313Z');

INSERT INTO coworkingview_cities (city_slug, city_name, country_code, currency, published, property_count, operator_count, entry_median, entry_min, entry_max, p25, p75, sample_size, as_of) VALUES
    ('abu-dhabi', 'Abu Dhabi', 'AE', 'AED', true, 2, 1, 1453, 1069, 7535, 1400, 2200, 2, '2026-10-27T21:06:48.313Z'),
    ('berlin', 'Berlin', 'DE', 'EUR', true, 85, 48, 265, 80, 2100, 219, 450, 85, '2026-10-27T21:06:48.313Z'),
    ('madrid', 'Madrid', 'ES', 'EUR', true, 10, 6, 325, 85, 1980, 195, 349, 10, '2026-10-27T21:06:48.313Z'),
    ('example-town', 'Example Town', NULL, NULL, false, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-10-27T21:06:48.313Z');

CREATE VIEW coworkingview_rates AS
SELECT
    price_index.city_slug,
    price_index.city_name,
    price_index.country_code,
    price_index.currency,
    price_index.product,
    price_index.unit,
    price_index.median,
    price_index.p25,
    price_index.p75,
    price_index.sample_size,
    price_index.property_count,
    price_index.operator_count,
    price_index.low_confidence,
    price_index.as_of,
    about.attribution,
    about.license,
    about.license_url
FROM coworkingview_price_index AS price_index
CROSS JOIN coworkingview_about AS about;

COMMENT ON VIEW coworkingview_rates IS
    'CoworkingView Price Index snapshot. attribution is the CC BY 4.0 credit; keep it with any figure you republish.';

-- SQL-standard bodies are parsed at CREATE EXTENSION time, so the table
-- references are pinned by OID and stay valid if the extension is relocated.
CREATE FUNCTION coworkingview_rate(city text, product_code text)
RETURNS numeric
LANGUAGE sql
STABLE
PARALLEL SAFE
STRICT
BEGIN ATOMIC
    SELECT median
    FROM coworkingview_price_index AS price_index
    WHERE price_index.city_slug = lower(btrim(city))
      AND price_index.product = lower(btrim(product_code));
END;

CREATE FUNCTION coworkingview_rate(city text)
RETURNS numeric
LANGUAGE sql
STABLE
PARALLEL SAFE
STRICT
BEGIN ATOMIC
    SELECT median
    FROM coworkingview_price_index AS price_index
    WHERE price_index.city_slug = lower(btrim(city))
      AND price_index.product = 'flex_desk';
END;

COMMENT ON FUNCTION coworkingview_rate(text, text) IS
    'Median from the embedded Price Index for a city slug and product (flex_desk, fix_desk, private_office, day_pass, meeting_room). NULL when that row is not in the snapshot.';

COMMENT ON FUNCTION coworkingview_rate(text) IS
    'Flex-desk median from the embedded Price Index for a city slug. NULL when the city is not in the snapshot.';

CREATE FUNCTION coworkingview_attribution()
RETURNS text
LANGUAGE sql
STABLE
PARALLEL SAFE
BEGIN ATOMIC
    SELECT attribution FROM coworkingview_about;
END;

COMMENT ON FUNCTION coworkingview_attribution() IS
    'CC BY 4.0 attribution for the embedded CoworkingView Price Index snapshot. Keep it with any figure you republish.';

GRANT SELECT ON coworkingview_about TO PUBLIC;
GRANT SELECT ON coworkingview_price_index TO PUBLIC;
GRANT SELECT ON coworkingview_cities TO PUBLIC;
GRANT SELECT ON coworkingview_rates TO PUBLIC;
