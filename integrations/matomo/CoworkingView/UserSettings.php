<?php

/**
 * CoworkingView dashboard widget for Matomo.
 *
 * @link    https://coworkingview.com
 * @license https://www.gnu.org/licenses/gpl-3.0.html GPL v3 or later
 */

namespace Piwik\Plugins\CoworkingView;

use Piwik\Settings\Setting;

/**
 * Per-user city override. Shown under Personal settings. Empty means "use the system city".
 */
class UserSettings extends \Piwik\Settings\Plugin\UserSettings
{
    use CityField;

    /**
     * @var Setting
     */
    public $city;

    protected function init()
    {
        $this->city = $this->makeCitySetting('', true, 'CoworkingView_CitySettingUserHelp');
    }
}
