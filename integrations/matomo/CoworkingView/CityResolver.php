<?php

/**
 * CoworkingView dashboard widget for Matomo.
 *
 * @link    https://coworkingview.com
 * @license https://www.gnu.org/licenses/gpl-3.0.html GPL v3 or later
 */

namespace Piwik\Plugins\CoworkingView;

/**
 * Resolves the city the widget will request: personal setting, then system setting, then berlin.
 */
class CityResolver
{
    /**
     * @return array{city: ?string, error: ?string}
     */
    public static function resolve()
    {
        $user = self::readSetting(true);
        if ($user['state'] === 'invalid') {
            return array('city' => null, 'error' => 'invalid');
        }
        if ($user['state'] === 'value') {
            return array('city' => $user['city'], 'error' => null);
        }

        $system = self::readSetting(false);
        if ($system['state'] === 'invalid') {
            return array('city' => null, 'error' => 'invalid');
        }
        if ($system['state'] === 'value') {
            return array('city' => $system['city'], 'error' => null);
        }

        return array('city' => 'berlin', 'error' => null);
    }

    /**
     * @param bool $userSetting
     * @return array{state: string, city: ?string}
     */
    private static function readSetting($userSetting)
    {
        try {
            $settings = $userSetting ? new UserSettings() : new SystemSettings();
            $raw = $settings->city->getValue();
        } catch (\Exception $exception) {
            return array('state' => 'missing', 'city' => null);
        }

        $value = strtolower(trim((string) $raw));
        if ($value === '') {
            return array('state' => 'missing', 'city' => null);
        }
        if (!CitySlug::isValid($value)) {
            return array('state' => 'invalid', 'city' => null);
        }

        return array('state' => 'value', 'city' => $value);
    }
}
