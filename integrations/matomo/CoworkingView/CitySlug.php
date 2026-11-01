<?php

/**
 * CoworkingView dashboard widget for Matomo.
 *
 * @link    https://coworkingview.com
 * @license https://www.gnu.org/licenses/gpl-3.0.html GPL v3 or later
 */

namespace Piwik\Plugins\CoworkingView;

/**
 * City slugs accepted by the public API path and query builders.
 */
class CitySlug
{
    /**
     * Same character set as the shared client specification, capped so the URL stays bounded.
     *
     * @param mixed $city
     * @return bool
     */
    public static function isValid($city)
    {
        if (!is_string($city)) {
            return false;
        }

        $length = strlen($city);
        if ($length < 1 || $length > 100) {
            return false;
        }

        return preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]*$/', $city) === 1;
    }
}
