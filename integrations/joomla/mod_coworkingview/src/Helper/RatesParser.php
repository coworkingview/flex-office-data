<?php

/**
 * @package     CoworkingView.Site
 * @subpackage  mod_coworkingview
 *
 * @copyright   (C) 2026 CoworkingView
 * @license     GNU General Public License version 2 or later; see LICENSE.txt
 */

namespace CoworkingView\Module\CoworkingView\Site\Helper;

// phpcs:disable PSR1.Files.SideEffects
\defined('_JEXEC') or die;
// phpcs:enable PSR1.Files.SideEffects

/**
 * Turns a Price Index payload into the rows the module shows.
 *
 * No I/O. The reading of GET /v1/market/rates matches the shared specification:
 * figures when that list is present and not empty, otherwise byType, then any
 * other city field that has median and sampleSize (dayPass, meetingRoom, and
 * later aggregates). Unpublished cities produce no rows.
 *
 * @since  1.0.0
 */
final class RatesParser
{
	/**
	 * Product order used by the Price Index clients in this repository.
	 *
	 * @var    list<string>
	 * @since  1.0.0
	 */
	public const PRODUCTS = [
		'flex_desk',
		'fix_desk',
		'private_office',
		'exclusive_bereich',
		'day_pass',
		'meeting_room',
		'event_space',
		'virtual_office',
		'membership',
	];

	/**
	 * Units for city-level statistic objects. Figures and byType are monthly.
	 *
	 * @var    array<string, string>
	 * @since  1.0.0
	 */
	private const STAT_UNITS = [
		'day_pass'       => 'day',
		'meeting_room'   => 'hour',
		'event_space'    => 'hour',
		'virtual_office' => 'month',
	];

	/**
	 * Whether a string is a city slug the API can be asked for.
	 *
	 * @param   string  $value  Candidate slug.
	 *
	 * @return  boolean
	 *
	 * @since   1.0.0
	 */
	public static function isCitySlug(string $value): bool
	{
		return preg_match('/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/', $value) === 1;
	}

	/**
	 * Whether a product code is one the API documents.
	 *
	 * @param   string  $value  Candidate product code. Empty means all products.
	 *
	 * @return  boolean
	 *
	 * @since   1.0.0
	 */
	public static function isProduct(string $value): bool
	{
		return $value === '' || in_array($value, self::PRODUCTS, true);
	}

	/**
	 * Whether a locale is one the API accepts.
	 *
	 * @param   string  $value  Candidate locale.
	 *
	 * @return  boolean
	 *
	 * @since   1.0.0
	 */
	public static function isLocale(string $value): bool
	{
		return in_array($value, ['en', 'de', 'es'], true);
	}

	/**
	 * An empty snapshot the template can render without further checks.
	 *
	 * @param   string       $code    Machine code for the error state.
	 * @param   string|null  $detail  Short text from the service, already plain.
	 * @param   int|null     $status  HTTP status, when the call returned one.
	 *
	 * @return  array<string, mixed>
	 *
	 * @since   1.0.0
	 */
	public static function failure(string $code, ?string $detail = null, ?int $status = null): array
	{
		return [
			'ok'          => false,
			'cacheable'   => false,
			'code'        => $code,
			'detail'      => $detail,
			'status'      => $status,
			'cityName'    => null,
			'citySlug'    => '',
			'countryCode' => null,
			'currency'    => null,
			'asOf'        => null,
			'asOfLabel'   => null,
			'attribution' => null,
			'license'     => null,
			'licenseUrl'  => null,
			'rows'        => [],
		];
	}

	/**
	 * Read one city out of a decoded Price Index body.
	 *
	 * The product filter and the item limit are applied by select(), so a
	 * cached parse can be shown with different parameters.
	 *
	 * @param   array<mixed>|null  $payload  Decoded JSON, or null when it was not JSON.
	 * @param   string             $city     City slug to keep.
	 *
	 * @return  array<string, mixed>
	 *
	 * @since   1.0.0
	 */
	public static function parse(?array $payload, string $city): array
	{
		if ($payload === null || !isset($payload['data']) || !is_array($payload['data']))
		{
			return self::failure('bad_response');
		}

		$data = $payload['data'];

		if (!isset($data['cities']) || !is_array($data['cities']))
		{
			return self::failure('bad_response');
		}

		$wanted = strtolower($city);
		$found  = self::findCity($data['cities'], $wanted);

		if ($found === null)
		{
			$failure = self::failure(self::unpublished($data, $wanted) ? 'unpublished' : 'unknown_city');
			$failure['cacheable'] = true;
			$failure['citySlug']  = $wanted;
			$failure['cityName']  = self::unpublishedName($data, $wanted);

			return $failure;
		}

		$rows = self::rowsForCity($found);

		return [
			'ok'          => true,
			'cacheable'   => true,
			'code'        => null,
			'detail'      => null,
			'status'      => null,
			'cityName'    => self::cityName($found),
			'citySlug'    => self::citySlug($found, $wanted),
			'countryCode' => self::optionalString($found['countryCode'] ?? null),
			'currency'    => self::optionalString($found['currency'] ?? null),
			'asOf'        => self::optionalString($data['asOf'] ?? null),
			'asOfLabel'   => self::asOfLabel(self::optionalString($data['asOf'] ?? null)),
			'attribution' => self::optionalString($data['attribution'] ?? null),
			'license'     => self::optionalString($data['license'] ?? null),
			'licenseUrl'  => self::httpsUrl(self::optionalString($data['licenseUrl'] ?? null)),
			'rows'        => $rows,
		];
	}

	/**
	 * Keep one product, when requested, and at most $limit rows.
	 *
	 * @param   array<string, mixed>  $snapshot  Result of parse().
	 * @param   string                $product   Product code, or empty for every product.
	 * @param   int                   $limit     How many rows to keep. Clamped to 1..12.
	 *
	 * @return  array<string, mixed>
	 *
	 * @since   1.0.0
	 */
	public static function select(array $snapshot, string $product, int $limit): array
	{
		$limit = max(1, min(12, $limit));
		$rows  = $snapshot['rows'] ?? [];

		if (!is_array($rows))
		{
			$rows = [];
		}

		if ($product !== '')
		{
			$filtered = [];

			foreach ($rows as $row)
			{
				if (is_array($row) && ($row['product'] ?? null) === $product)
				{
					$filtered[] = $row;
				}
			}

			$rows = $filtered;
		}

		$snapshot['rows'] = array_slice(array_values($rows), 0, $limit);

		return $snapshot;
	}

	/**
	 * Plain text from an RFC 9457 problem body.
	 *
	 * @param   array<mixed>|null  $body  Decoded problem JSON.
	 *
	 * @return  string|null
	 *
	 * @since   1.0.0
	 */
	public static function problemDetail(?array $body): ?string
	{
		if ($body === null)
		{
			return null;
		}

		$parts = [];

		foreach (['title', 'detail'] as $key)
		{
			if (isset($body[$key]) && is_string($body[$key]) && trim($body[$key]) !== '')
			{
				$parts[] = trim($body[$key]);
			}
		}

		if ($parts === [] && isset($body['errors']) && is_array($body['errors']))
		{
			foreach ($body['errors'] as $error)
			{
				if (is_array($error) && isset($error['message']) && is_string($error['message']))
				{
					$message = trim($error['message']);

					if ($message !== '')
					{
						$parts[] = $message;
					}
				}
			}
		}

		if ($parts === [])
		{
			return null;
		}

		$text = trim((string) preg_replace('/\s+/', ' ', strip_tags(implode(' ', $parts))));

		if ($text === '')
		{
			return null;
		}

		if (strlen($text) > 240)
		{
			$text = substr($text, 0, 237) . '...';
		}

		return $text;
	}

	/**
	 * Format an amount the way the API wrote a whole number, without grouping.
	 *
	 * @param   float  $amount  Amount to format.
	 *
	 * @return  string
	 *
	 * @since   1.0.0
	 */
	public static function formatAmount(float $amount): string
	{
		if (floor($amount) === $amount)
		{
			return (string) (int) $amount;
		}

		$text = number_format($amount, 2, '.', '');
		$text = rtrim(rtrim($text, '0'), '.');

		return $text;
	}

	/**
	 * Amount plus currency code.
	 *
	 * @param   float        $amount    Amount to format.
	 * @param   string|null  $currency  ISO currency code.
	 *
	 * @return  string
	 *
	 * @since   1.0.0
	 */
	public static function formatMoney(float $amount, ?string $currency): string
	{
		$text = self::formatAmount($amount);

		if ($currency === null || $currency === '')
		{
			return $text;
		}

		return $text . ' ' . $currency;
	}

	/**
	 * Keep an https URL. Anything else is dropped before it reaches the template.
	 *
	 * @param   string|null  $value  Candidate URL.
	 *
	 * @return  string|null
	 *
	 * @since   1.0.0
	 */
	public static function httpsUrl(?string $value): ?string
	{
		if ($value === null || preg_match('#\Ahttps://[^\s]+\z#', $value) !== 1)
		{
			return null;
		}

		$parts = parse_url($value);

		if (!is_array($parts) || ($parts['scheme'] ?? '') !== 'https' || empty($parts['host']))
		{
			return null;
		}

		return $value;
	}

	/**
	 * Find the published city object for a lower-case slug.
	 *
	 * @param   array<mixed>  $cities  data.cities.
	 * @param   string        $wanted  Lower-case slug.
	 *
	 * @return  array<mixed>|null
	 *
	 * @since   1.0.0
	 */
	private static function findCity(array $cities, string $wanted): ?array
	{
		foreach ($cities as $city)
		{
			if (!is_array($city))
			{
				continue;
			}

			$slug = self::citySlug($city, '');

			if ($slug !== '' && strtolower($slug) === $wanted)
			{
				return $city;
			}
		}

		return null;
	}

	/**
	 * Whether the slug is listed under unpublished.
	 *
	 * @param   array<mixed>  $data    data object.
	 * @param   string        $wanted  Lower-case slug.
	 *
	 * @return  boolean
	 *
	 * @since   1.0.0
	 */
	private static function unpublished(array $data, string $wanted): bool
	{
		if (!isset($data['unpublished']) || !is_array($data['unpublished']))
		{
			return false;
		}

		foreach ($data['unpublished'] as $city)
		{
			if (is_array($city) && strtolower(self::citySlug($city, '')) === $wanted && self::citySlug($city, '') !== '')
			{
				return true;
			}
		}

		return false;
	}

	/**
	 * Display name of an unpublished city, when the payload has one.
	 *
	 * @param   array<mixed>  $data    data object.
	 * @param   string        $wanted  Lower-case slug.
	 *
	 * @return  string|null
	 *
	 * @since   1.0.0
	 */
	private static function unpublishedName(array $data, string $wanted): ?string
	{
		if (!isset($data['unpublished']) || !is_array($data['unpublished']))
		{
			return null;
		}

		foreach ($data['unpublished'] as $city)
		{
			if (!is_array($city) || strtolower(self::citySlug($city, '')) !== $wanted)
			{
				continue;
			}

			return self::cityName($city);
		}

		return null;
	}

	/**
	 * Price rows for one published city, in the shared product order.
	 *
	 * @param   array<mixed>  $city  One data.cities item.
	 *
	 * @return  list<array<string, mixed>>
	 *
	 * @since   1.0.0
	 */
	private static function rowsForCity(array $city): array
	{
		$items = [];

		if (isset($city['figures']) && is_array($city['figures']) && $city['figures'] !== [])
		{
			$items = $city['figures'];
		}
		elseif (isset($city['byType']) && is_array($city['byType']))
		{
			$items = $city['byType'];
		}

		$rows     = [];
		$currency = self::optionalString($city['currency'] ?? null);

		foreach ($items as $item)
		{
			$row = self::rowFromItem($item, 'month', null, $currency);

			if ($row !== null)
			{
				$rows[] = $row;
			}
		}

		foreach ($city as $key => $value)
		{
			if (!is_string($key) || !self::isStat($value))
			{
				continue;
			}

			$product = self::snake($key);
			$unit    = self::STAT_UNITS[$product] ?? null;
			$row     = self::rowFromItem($value, $unit, $product, $currency);

			if ($row !== null)
			{
				$rows[] = $row;
			}
		}

		usort(
			$rows,
			static function (array $left, array $right): int {
				$order     = array_flip(self::PRODUCTS);
				$leftRank  = $order[$left['product']] ?? 100;
				$rightRank = $order[$right['product']] ?? 100;

				if ($leftRank !== $rightRank)
				{
					return $leftRank <=> $rightRank;
				}

				return strcmp((string) $left['product'], (string) $right['product']);
			}
		);

		return $rows;
	}

	/**
	 * One table row, or null when the item has no product or no median.
	 *
	 * @param   mixed        $item      A figures item, a byType item, or a city-level stat.
	 * @param   string|null  $unit      month, day, hour, or null.
	 * @param   string|null  $product   Product code when the item is a city-level stat.
	 * @param   string|null  $currency  City currency, used when the money object has none.
	 *
	 * @return  array<string, mixed>|null
	 *
	 * @since   1.0.0
	 */
	private static function rowFromItem(mixed $item, ?string $unit, ?string $product, ?string $currency): ?array
	{
		if (!is_array($item))
		{
			return null;
		}

		if ($product === null)
		{
			$option = $item['optionType'] ?? null;

			if (!is_string($option) || $option === '')
			{
				return null;
			}

			$product = $option;
		}

		$median = self::amount($item['median'] ?? null);

		if ($median === null)
		{
			return null;
		}

		$rowCurrency = self::moneyCurrency($item['median'] ?? null) ?? $currency;
		$sample      = self::countOrNull($item['sampleSize'] ?? null);

		return [
			'product'        => $product,
			'unit'           => $unit,
			'median'         => $median,
			'currency'       => $rowCurrency,
			'p25'            => self::amount(array_key_exists('p25', $item) ? $item['p25'] : null),
			'p75'            => self::amount(array_key_exists('p75', $item) ? $item['p75'] : null),
			'sampleSize'     => $sample,
			'lowConfidence'  => is_int($sample) && $sample < 10,
		];
	}

	/**
	 * A city-level value is a price statistic when it has median and sampleSize.
	 *
	 * @param   mixed  $value  One field of the city object.
	 *
	 * @return  boolean
	 *
	 * @since   1.0.0
	 */
	private static function isStat(mixed $value): bool
	{
		return is_array($value)
			&& array_key_exists('median', $value)
			&& array_key_exists('sampleSize', $value);
	}

	/**
	 * dayPass becomes day_pass.
	 *
	 * @param   string  $key  City field name.
	 *
	 * @return  string
	 *
	 * @since   1.0.0
	 */
	private static function snake(string $key): string
	{
		$snake = preg_replace('/(?<!^)(?=[A-Z])/', '_', $key);

		return strtolower((string) $snake);
	}

	/**
	 * Money amount, or null when the object is absent.
	 *
	 * @param   mixed  $money  A money object or null.
	 *
	 * @return  float|null
	 *
	 * @since   1.0.0
	 */
	private static function amount(mixed $money): ?float
	{
		if (!is_array($money) || !array_key_exists('amount', $money))
		{
			return null;
		}

		$amount = $money['amount'];

		if (is_int($amount) || is_float($amount))
		{
			return (float) $amount;
		}

		if (is_string($amount) && is_numeric($amount))
		{
			return (float) $amount;
		}

		return null;
	}

	/**
	 * Currency code on a money object.
	 *
	 * @param   mixed  $money  A money object or null.
	 *
	 * @return  string|null
	 *
	 * @since   1.0.0
	 */
	private static function moneyCurrency(mixed $money): ?string
	{
		if (!is_array($money))
		{
			return null;
		}

		return self::optionalString($money['currency'] ?? null);
	}

	/**
	 * Non-negative integer sample size.
	 *
	 * @param   mixed  $value  sampleSize as decoded from JSON.
	 *
	 * @return  integer|null
	 *
	 * @since   1.0.0
	 */
	private static function countOrNull(mixed $value): ?int
	{
		if (is_int($value) && $value >= 0)
		{
			return $value;
		}

		if (is_float($value) && $value >= 0 && floor($value) === $value)
		{
			return (int) $value;
		}

		return null;
	}

	/**
	 * Trim a string field, or null when it is missing or blank.
	 *
	 * @param   mixed  $value  JSON value.
	 *
	 * @return  string|null
	 *
	 * @since   1.0.0
	 */
	private static function optionalString(mixed $value): ?string
	{
		if (!is_string($value))
		{
			return null;
		}

		$value = trim($value);

		return $value === '' ? null : $value;
	}

	/**
	 * Calendar date from an ISO timestamp, or the original string.
	 *
	 * @param   string|null  $value  asOf.
	 *
	 * @return  string|null
	 *
	 * @since   1.0.0
	 */
	private static function asOfLabel(?string $value): ?string
	{
		if ($value === null)
		{
			return null;
		}

		if (preg_match('/\A(\d{4}-\d{2}-\d{2})/', $value, $match) === 1)
		{
			return $match[1];
		}

		return $value;
	}

	/**
	 * city.slug.
	 *
	 * @param   array<mixed>  $city      A city object.
	 * @param   string        $fallback  Value when the slug is absent.
	 *
	 * @return  string
	 *
	 * @since   1.0.0
	 */
	private static function citySlug(array $city, string $fallback): string
	{
		$ref = $city['city'] ?? null;

		if (!is_array($ref))
		{
			return $fallback;
		}

		$slug = self::optionalString($ref['slug'] ?? null);

		return $slug ?? $fallback;
	}

	/**
	 * city.name.
	 *
	 * @param   array<mixed>  $city  A city object.
	 *
	 * @return  string|null
	 *
	 * @since   1.0.0
	 */
	private static function cityName(array $city): ?string
	{
		$ref = $city['city'] ?? null;

		if (!is_array($ref))
		{
			return null;
		}

		return self::optionalString($ref['name'] ?? null);
	}
}
