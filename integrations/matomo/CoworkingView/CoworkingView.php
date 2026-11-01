<?php

/**
 * CoworkingView dashboard widget for Matomo.
 *
 * @link    https://coworkingview.com
 * @license https://www.gnu.org/licenses/gpl-3.0.html GPL v3 or later
 */

namespace Piwik\Plugins\CoworkingView;

class CoworkingView extends \Piwik\Plugin
{
    public function registerEvents()
    {
        return array(
            'AssetManager.getStylesheetFiles' => 'getStylesheetFiles',
        );
    }

    /**
     * @param string[] $stylesheets
     */
    public function getStylesheetFiles(&$stylesheets)
    {
        $stylesheets[] = 'plugins/CoworkingView/stylesheets/widget.css';
    }

    public function isTrackerPlugin()
    {
        return false;
    }
}
