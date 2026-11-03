CREATE EXTENSION coworkingview;

SET TIME ZONE 'UTC';
SET datestyle = iso;

SELECT coworkingview_attribution();

SELECT license, license_url, as_of, length(scope) AS scope_length
FROM coworkingview_about;

SELECT count(*) AS price_rows FROM coworkingview_price_index;

SELECT count(*) AS city_rows FROM coworkingview_cities;

SELECT count(*) AS view_rows FROM coworkingview_rates;

SELECT count(*) AS confidence_mismatches
FROM coworkingview_price_index
WHERE low_confidence IS DISTINCT FROM (sample_size < 10);

SELECT coworkingview_rate('berlin');

SELECT coworkingview_rate('Berlin');

SELECT coworkingview_rate(' berlin ');

SELECT coworkingview_rate('madrid', 'private_office');

SELECT coworkingview_rate('MADRID', 'DAY_PASS');

SELECT coworkingview_rate('abu-dhabi', 'flex_desk');

SELECT coworkingview_rate('example-town');

SELECT coworkingview_rate('no-such-city');

SELECT coworkingview_rate('berlin', 'nope');

SELECT coworkingview_rate(NULL::text) IS NULL AS null_city;

SELECT coworkingview_rate('berlin', NULL::text) IS NULL AS null_product;

SELECT city_slug, product, unit, median, p25, p75, sample_size,
       property_count, operator_count, low_confidence
FROM coworkingview_price_index
ORDER BY city_slug,
    CASE product
        WHEN 'flex_desk' THEN 1
        WHEN 'fix_desk' THEN 2
        WHEN 'private_office' THEN 3
        WHEN 'exclusive_bereich' THEN 4
        WHEN 'day_pass' THEN 5
        WHEN 'meeting_room' THEN 6
        WHEN 'event_space' THEN 7
        WHEN 'virtual_office' THEN 8
        WHEN 'membership' THEN 9
        ELSE 10
    END,
    product;

SELECT city_slug, city_name, country_code, currency, published,
       property_count, operator_count, entry_median, entry_min, entry_max,
       p25, p75, sample_size
FROM coworkingview_cities
ORDER BY published DESC, city_slug;

SELECT city_slug, product, median, license,
       attribution = (SELECT attribution FROM coworkingview_about) AS attribution_matches
FROM coworkingview_rates
WHERE city_slug = 'berlin' AND product = 'flex_desk';

SELECT published,
       entry_median IS NULL AS entry_median_is_null,
       currency IS NULL AS currency_is_null
FROM coworkingview_cities
WHERE city_slug = 'example-town';

SELECT p25 IS NULL AS p25_is_null, p75 IS NULL AS p75_is_null
FROM coworkingview_price_index
WHERE city_slug = 'berlin' AND product = 'day_pass';

CREATE SCHEMA cvtest;

ALTER EXTENSION coworkingview SET SCHEMA cvtest;

SELECT cvtest.coworkingview_rate('berlin');

SELECT cvtest.coworkingview_rate('madrid', 'meeting_room');

SELECT cvtest.coworkingview_attribution();

SELECT count(*) AS moved_rows FROM cvtest.coworkingview_rates;

ALTER EXTENSION coworkingview SET SCHEMA public;

DROP SCHEMA cvtest;
