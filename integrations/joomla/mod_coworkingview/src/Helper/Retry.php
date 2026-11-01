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
 * How long to wait before the single retry of a 429 or 5xx response.
 *
 * The wait is Retry-After, otherwise RateLimit-Reset, otherwise 2 seconds,
 * and never more than 10. Retry-After may be delta-seconds or an HTTP date.
 * RateLimit-Reset is delta-seconds only.
 *
 * @since  1.0.0
 */
final class Retry
{
	/**
	 * Seconds to sleep before the one retry.
	 *
	 * @param   string|null  $retryAfter      Retry-After header, if the response sent one.
	 * @param   string|null  $rateLimitReset  RateLimit-Reset header, if the response sent one.
	 * @param   int|null     $now             Unix time used to read an HTTP-date Retry-After.
	 *
	 * @return  integer
	 *
	 * @since   1.0.0
	 */
	public static function seconds(?string $retryAfter, ?string $rateLimitReset, ?int $now = null): int
	{
		$now  = $now ?? time();
		$wait = self::delay($retryAfter, true, $now);

		if ($wait === null)
		{
			$wait = self::delay($rateLimitReset, false, $now);
		}

		if ($wait === null)
		{
			$wait = 2.0;
		}

		if ($wait < 0)
		{
			$wait = 0.0;
		}

		if ($wait > 10)
		{
			$wait = 10.0;
		}

		return (int) ceil($wait);
	}

	/**
	 * Parse one delay header into seconds.
	 *
	 * @param   string|null  $value      Header value.
	 * @param   bool         $allowDate  Whether an HTTP-date is accepted.
	 * @param   int          $now        Unix time for an HTTP-date.
	 *
	 * @return  float|null
	 *
	 * @since   1.0.0
	 */
	private static function delay(?string $value, bool $allowDate, int $now): ?float
	{
		if ($value === null)
		{
			return null;
		}

		$value = trim($value);

		if ($value === '')
		{
			return null;
		}

		if (is_numeric($value))
		{
			return max(0.0, (float) $value);
		}

		if (!$allowDate)
		{
			return null;
		}

		$when = strtotime($value);

		if ($when === false)
		{
			return null;
		}

		return max(0.0, (float) ($when - $now));
	}
}
