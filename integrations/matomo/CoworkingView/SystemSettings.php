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
 * System-wide default city. Shown under Administration → System → General settings.
 */
class SystemSettings extends \Piwik\Settings\Plugin\SystemSettings
{
    use CityField;

    /**
     * @var Setting
     */
    public $city;

    protected function init()
    {
        $this->city = $this->makeCitySetting('berlin', false, 'CoworkingView_CitySettingSystemHelp');
    }
}
