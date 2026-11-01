<?php

/**
 * @package     CoworkingView.Site
 * @subpackage  mod_coworkingview
 *
 * @copyright   (C) 2026 CoworkingView
 * @license     GNU General Public License version 2 or later; see LICENSE.txt
 */

namespace CoworkingView\Module\CoworkingView\Site\Helper;

use Joomla\CMS\Application\CMSApplicationInterface;
use Joomla\CMS\Cache\CacheControllerFactoryInterface;
use Joomla\CMS\Http\HttpFactory;
use Joomla\Registry\Registry;

// phpcs:disable PSR1.Files.SideEffects
\defined('_JEXEC') or die;
// phpcs:enable PSR1.Files.SideEffects

/**
 * Loads indicative Price Index figures for one city.
 *
 * The only network call is HTTPS GET https://api.coworkingview.com/v1/market/rates
 * with the chosen city and language. There is no API key. A successful reading
 * is cached for the number of minutes set on the module. Failures are not cached.
 *
 * @since  1.0.0
 */
final class CoworkingViewHelper
{
	/**
	 * Extension version. Kept in step with the manifest.
	 *
	 * @var    string
	 * @since  1.0.0
	 */
	public const VERSION = '1.0.0';

	/**
	 * Public API origin. The module does not accept another host.
	 *
	 * @var    string
	 * @since  1.0.0
	 */
	private const API = 'https://api.coworkingview.com';

	/**
	 * Price rows for the module layout.
	 *
	 * @param   Registry                  $params  Module parameters.
	 * @param   CMSApplicationInterface   $app     The site application, used for the cache.
	 *
	 * @return  array<string, mixed>
	 *
	 * @since   1.0.0
	 */
	public function getSnapshot(Registry $params, CMSApplicationInterface $app): array
	{
		try
		{
			return $this->load($params, $app);
		}
		catch (\Throwable $exception)
		{
			unset($exception);

			return RatesParser::failure('unavailable');
		}
	}

	/**
	 * Validate the parameters, read the cache or the API, then apply the filter.
	 *
	 * @param   Registry                 $params  Module parameters.
	 * @param   CMSApplicationInterface  $app     The site application.
	 *
	 * @return  array<string, mixed>
	 *
	 * @since   1.0.0
	 */
	private function load(Registry $params, CMSApplicationInterface $app): array
	{
		$city    = $this->stringParam($params, 'city', 'berlin');
		$product = $this->stringParam($params, 'product', '');
		$locale  = $this->stringParam($params, 'language', 'en');
		$count   = $params->get('count', 6);
		$cache   = $params->get('cache_time', 60);
		$limit   = is_numeric($count) ? (int) $count : 0;
		$minutes = is_numeric($cache) ? (int) $cache : 0;

		if (!RatesParser::isCitySlug($city))
		{
			return RatesParser::failure('bad_city');
		}

		if (!RatesParser::isProduct($product))
		{
			return RatesParser::failure('bad_product');
		}

		if (!RatesParser::isLocale($locale))
		{
			$locale = 'en';
		}

		if ($limit < 1)
		{
			$limit = 1;
		}

		if ($limit > 12)
		{
			$limit = 12;
		}

		if ($minutes < 10)
		{
			$minutes = 10;
		}

		if ($minutes > 1440)
		{
			$minutes = 1440;
		}

		$city   = strtolower($city);
		$parsed = $this->cached($app, $city, $locale, $minutes);

		return RatesParser::select($parsed, $product, $limit);
	}

	/**
	 * A string parameter, or the default when the stored value is not a string.
	 *
	 * @param   Registry  $params   Module parameters.
	 * @param   string    $name     Parameter name.
	 * @param   string    $default  Value used when the parameter is absent.
	 *
	 * @return  string
	 *
	 * @since   1.0.0
	 */
	private function stringParam(Registry $params, string $name, string $default): string
	{
		$value = $params->get($name, $default);

		if (!is_string($value))
		{
			return $default;
		}

		return trim($value);
	}

	/**
	 * Return a cached parse, or fetch and store one.
	 *
	 * @param   CMSApplicationInterface  $app      The site application.
	 * @param   string                   $city     Lower-case city slug.
	 * @param   string                   $locale   en, de, or es.
	 * @param   int                      $minutes  Cache lifetime in minutes.
	 *
	 * @return  array<string, mixed>
	 *
	 * @since   1.0.0
	 */
	private function cached(CMSApplicationInterface $app, string $city, string $locale, int $minutes): array
	{
		$id    = 'rates.' . self::VERSION . '.' . $city . '.' . $locale;
		$cache = $this->cache($app, $minutes);

		if ($cache !== null)
		{
			$stored = $cache->get($id);

			if (is_array($stored) && ($stored['cacheable'] ?? false) === true)
			{
				return $stored;
			}
		}

		$parsed = $this->fetch($city, $locale);

		if ($cache !== null && ($parsed['cacheable'] ?? false) === true)
		{
			$cache->store($parsed, $id);
		}

		return $parsed;
	}

	/**
	 * Module cache, or null when the cache service is not available.
	 *
	 * Caching is turned on for this group even when the site cache is off,
	 * so the cache time parameter is the one that applies.
	 *
	 * @param   CMSApplicationInterface  $app      The site application.
	 * @param   int                      $minutes  Cache lifetime in minutes.
	 *
	 * @return  object|null
	 *
	 * @since   1.0.0
	 */
	private function cache(CMSApplicationInterface $app, int $minutes): ?object
	{
		if (!method_exists($app, 'getContainer'))
		{
			return null;
		}

		$container = $app->getContainer();

		if (!$container->has(CacheControllerFactoryInterface::class))
		{
			return null;
		}

		$factory = $container->get(CacheControllerFactoryInterface::class);

		if (!$factory instanceof CacheControllerFactoryInterface)
		{
			return null;
		}

		$cache = $factory->createCacheController('output', ['defaultgroup' => 'mod_coworkingview']);
		$cache->setCaching(true);
		$cache->setLifeTime($minutes);

		return $cache;
	}

	/**
	 * GET the Price Index for one city.
	 *
	 * @param   string  $city    Lower-case city slug.
	 * @param   string  $locale  en, de, or es.
	 *
	 * @return  array<string, mixed>
	 *
	 * @since   1.0.0
	 */
	private function fetch(string $city, string $locale): array
	{
		$url = self::API . '/v1/market/rates?' . http_build_query(
			[
				'locale' => $locale,
				'city'   => $city,
			],
			'',
			'&',
			PHP_QUERY_RFC3986
		);

		$result = $this->getJson($url);

		if ($result['body'] === null)
		{
			return RatesParser::failure($result['code'], $result['detail'], $result['status']);
		}

		return RatesParser::parse($result['body'], $city);
	}

	/**
	 * One JSON GET, with a single retry on HTTP 429 or 5xx.
	 *
	 * @param   string  $url  Absolute URL on api.coworkingview.com.
	 *
	 * @return  array{code: string, detail: ?string, status: ?int, body: ?array}
	 *
	 * @since   1.0.0
	 */
	private function getJson(string $url): array
	{
		$options = new Registry;
		$options->set(
			'userAgent',
			'mod_coworkingview/' . self::VERSION . ' (+https://github.com/coworkingview/flex-office-data)'
		);

		try
		{
			$http = HttpFactory::getHttp($options);
		}
		catch (\Throwable $exception)
		{
			unset($exception);

			return ['code' => 'unavailable', 'detail' => null, 'status' => null, 'body' => null];
		}

		$response = null;

		for ($attempt = 0; $attempt < 2; $attempt++)
		{
			try
			{
				$response = $http->get($url, ['Accept' => 'application/json'], 20);
			}
			catch (\Throwable $exception)
			{
				unset($exception);

				return ['code' => 'unavailable', 'detail' => null, 'status' => null, 'body' => null];
			}

			$status = $this->status($response);

			if (($status === 429 || $status >= 500) && $attempt === 0)
			{
				$seconds = Retry::seconds(
					$this->header($response, 'Retry-After'),
					$this->header($response, 'RateLimit-Reset')
				);

				if ($seconds > 0)
				{
					sleep($seconds);
				}

				continue;
			}

			break;
		}

		if (!is_object($response))
		{
			return ['code' => 'unavailable', 'detail' => null, 'status' => null, 'body' => null];
		}

		$status = $this->status($response);
		$decoded = $this->decodeBody($response);

		if ($status < 200 || $status >= 300)
		{
			$code = $status === 0 ? 'unavailable' : 'http';

			return [
				'code'   => $code,
				'detail' => RatesParser::problemDetail($decoded),
				'status' => $status === 0 ? null : $status,
				'body'   => null,
			];
		}

		if ($decoded === null)
		{
			return ['code' => 'bad_response', 'detail' => null, 'status' => $status, 'body' => null];
		}

		return ['code' => '', 'detail' => null, 'status' => $status, 'body' => $decoded];
	}

	/**
	 * HTTP status from a Joomla HTTP response.
	 *
	 * @param   object  $response  Response from Http::get().
	 *
	 * @return  integer
	 *
	 * @since   1.0.0
	 */
	private function status(object $response): int
	{
		$code = $response->code ?? 0;

		return is_numeric($code) ? (int) $code : 0;
	}

	/**
	 * First value of a response header, matched without case.
	 *
	 * @param   object  $response  Response from Http::get().
	 * @param   string  $name      Header name.
	 *
	 * @return  string|null
	 *
	 * @since   1.0.0
	 */
	private function header(object $response, string $name): ?string
	{
		$headers = $response->headers ?? null;

		if (!is_array($headers))
		{
			return null;
		}

		foreach ($headers as $key => $value)
		{
			if (!is_string($key) || strcasecmp($key, $name) !== 0)
			{
				continue;
			}

			if (is_array($value))
			{
				$value = $value[0] ?? '';
			}

			if (!is_string($value))
			{
				return null;
			}

			$value = trim($value);

			return $value === '' ? null : $value;
		}

		return null;
	}

	/**
	 * Decode a JSON body, or null when it is not a JSON object or array.
	 *
	 * @param   object  $response  Response from Http::get().
	 *
	 * @return  array<mixed>|null
	 *
	 * @since   1.0.0
	 */
	private function decodeBody(object $response): ?array
	{
		$raw = $response->body ?? '';

		if (!is_string($raw) || $raw === '')
		{
			return null;
		}

		$decoded = json_decode($raw, true);

		return is_array($decoded) ? $decoded : null;
	}
}
