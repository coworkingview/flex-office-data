<?php

/**
 * CoworkingView dashboard widget for Matomo.
 *
 * @link    https://coworkingview.com
 * @license https://www.gnu.org/licenses/gpl-3.0.html GPL v3 or later
 */

namespace Piwik\Plugins\CoworkingView\Widgets;

use Piwik\Piwik;
use Piwik\Plugins\CoworkingView\ApiClient;
use Piwik\Plugins\CoworkingView\CityResolver;
use Piwik\Plugins\CoworkingView\MarketSnapshot;
use Piwik\Widget\Widget;
use Piwik\Widget\WidgetConfig;

class FlexibleOfficePrices extends Widget
{
    public static function configure(WidgetConfig $config)
    {
        $config->setCategoryId('CoworkingView_Category');
        $config->setName('CoworkingView_WidgetName');
        $config->setOrder(20);
        $config->setIsWide();
    }

    public function render()
    {
        try {
            return $this->renderPrices();
        } catch (\Exception $exception) {
            return $this->renderTemplate('flexibleOfficePrices', $this->viewData($this->failedSnapshot('')));
        }
    }

    /**
     * @return string
     */
    private function renderPrices()
    {
        $resolved = CityResolver::resolve();
        if ($resolved['error'] !== null || !is_string($resolved['city'])) {
            $snapshot = $this->failedSnapshot('');
            $snapshot['ratesError'] = 'invalid';
            $snapshot['propertiesError'] = null;

            return $this->renderTemplate('flexibleOfficePrices', $this->viewData($snapshot));
        }

        $snapshot = (new ApiClient())->load($resolved['city']);

        return $this->renderTemplate('flexibleOfficePrices', $this->viewData($snapshot));
    }

    /**
     * @param string $city
     * @return array
     */
    private function failedSnapshot($city)
    {
        return array(
            'citySlug' => $city,
            'cityName' => null,
            'countryCode' => null,
            'rows' => array(),
            'asOf' => null,
            'attribution' => null,
            'workspaceCount' => null,
            'ratesError' => MarketSnapshot::ERROR_UNAVAILABLE,
            'ratesDetail' => null,
            'propertiesError' => MarketSnapshot::ERROR_UNAVAILABLE,
            'propertiesDetail' => null,
        );
    }

    /**
     * @param array $snapshot
     * @return array
     */
    private function viewData($snapshot)
    {
        $rows = array();
        if (isset($snapshot['rows']) && is_array($snapshot['rows'])) {
            foreach ($snapshot['rows'] as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $rows[] = array(
                    'label' => $this->productLabel(isset($row['product']) ? $row['product'] : ''),
                    'median' => $this->cell(isset($row['median']) ? $row['median'] : null),
                    'p25' => $this->cell(isset($row['p25']) ? $row['p25'] : null),
                    'p75' => $this->cell(isset($row['p75']) ? $row['p75'] : null),
                    'unit' => $this->unitLabel(isset($row['unit']) ? $row['unit'] : null),
                    'sampleSize' => $this->cell(isset($row['sampleSize']) ? $row['sampleSize'] : null),
                );
            }
        }

        return array(
            'citySlug' => isset($snapshot['citySlug']) ? (string) $snapshot['citySlug'] : '',
            'cityName' => isset($snapshot['cityName']) ? $snapshot['cityName'] : null,
            'countryCode' => isset($snapshot['countryCode']) ? $snapshot['countryCode'] : null,
            'rows' => $rows,
            'asOf' => isset($snapshot['asOf']) ? $snapshot['asOf'] : null,
            'attribution' => isset($snapshot['attribution']) ? $snapshot['attribution'] : null,
            'workspaceCount' => array_key_exists('workspaceCount', $snapshot) ? $snapshot['workspaceCount'] : null,
            'ratesError' => $this->errorText(
                isset($snapshot['ratesError']) ? $snapshot['ratesError'] : null,
                isset($snapshot['ratesDetail']) ? $snapshot['ratesDetail'] : null,
                'CoworkingView_RatesError'
            ),
            'propertiesError' => $this->errorText(
                isset($snapshot['propertiesError']) ? $snapshot['propertiesError'] : null,
                isset($snapshot['propertiesDetail']) ? $snapshot['propertiesDetail'] : null,
                'CoworkingView_PropertiesError'
            ),
        );
    }

    /**
     * @param string $product
     * @return string
     */
    private function productLabel($product)
    {
        if (!is_string($product) || $product === '') {
            return Piwik::translate('CoworkingView_Unavailable');
        }

        $key = 'CoworkingView_Product_' . $product;
        $label = Piwik::translate($key);
        if ($label === $key) {
            return $product;
        }

        return $label;
    }

    /**
     * @param mixed $unit
     * @return string
     */
    private function unitLabel($unit)
    {
        if (!is_string($unit) || $unit === '') {
            return Piwik::translate('CoworkingView_Unavailable');
        }

        $key = 'CoworkingView_Unit_' . $unit;
        $label = Piwik::translate($key);
        if ($label === $key) {
            return $unit;
        }

        return $label;
    }

    /**
     * @param mixed $value
     * @return string
     */
    private function cell($value)
    {
        if ($value === null || $value === '') {
            return Piwik::translate('CoworkingView_Unavailable');
        }

        return (string) $value;
    }

    /**
     * @param mixed $code
     * @param mixed $detail
     * @param string $fallbackKey
     * @return string|null
     */
    private function errorText($code, $detail, $fallbackKey)
    {
        if ($code === null || $code === '') {
            return null;
        }
        if ($code === 'invalid') {
            return Piwik::translate('CoworkingView_CityInvalid');
        }

        $message = Piwik::translate($fallbackKey);
        if (is_string($detail) && $detail !== '') {
            $message .= ' ' . $detail;
        }

        return $message;
    }
}
