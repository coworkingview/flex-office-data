<?php

/**
 * CoworkingView dashboard widget for Matomo.
 *
 * @link    https://coworkingview.com
 * @license https://www.gnu.org/licenses/gpl-3.0.html GPL v3 or later
 */

namespace Piwik\Plugins\CoworkingView;

use Piwik\Piwik;
use Piwik\Settings\FieldConfig;

trait CityField
{
    /**
     * @param string $default
     * @param bool $allowEmpty
     * @param string $helpKey
     * @return \Piwik\Settings\Setting
     */
    protected function makeCitySetting($default, $allowEmpty, $helpKey)
    {
        return $this->makeSetting('city', $default, FieldConfig::TYPE_STRING, function (FieldConfig $field) use ($allowEmpty, $helpKey) {
            $field->title = Piwik::translate('CoworkingView_CitySettingTitle');
            $field->introduction = Piwik::translate('CoworkingView_CitySettingIntroduction');
            $field->uiControl = FieldConfig::UI_CONTROL_TEXT;
            $field->description = Piwik::translate($helpKey);
            $field->uiControlAttributes = array('size' => 24);
            $field->transform = function ($value) {
                return strtolower(trim((string) $value));
            };
            $field->validate = function ($value) use ($allowEmpty) {
                $city = trim((string) $value);
                if ($city === '') {
                    if ($allowEmpty) {
                        return;
                    }

                    throw new \Exception(Piwik::translate('CoworkingView_CityInvalid'));
                }

                if (!CitySlug::isValid($city)) {
                    throw new \Exception(Piwik::translate('CoworkingView_CityInvalid'));
                }
            };
        });
    }
}
