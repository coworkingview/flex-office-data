<?php

/**
 * @package     CoworkingView.Site
 * @subpackage  mod_coworkingview
 *
 * @copyright   (C) 2026 CoworkingView
 * @license     GNU General Public License version 2 or later; see LICENSE.txt
 */

namespace CoworkingView\Module\CoworkingView\Site\Dispatcher;

use CoworkingView\Module\CoworkingView\Site\Helper\RatesParser;
use Joomla\CMS\Dispatcher\AbstractModuleDispatcher;
use Joomla\CMS\Document\HtmlDocument;
use Joomla\CMS\Helper\HelperFactoryAwareInterface;
use Joomla\CMS\Helper\HelperFactoryAwareTrait;
use Joomla\CMS\Uri\Uri;

// phpcs:disable PSR1.Files.SideEffects
\defined('_JEXEC') or die;
// phpcs:enable PSR1.Files.SideEffects

/**
 * Dispatcher for CoworkingView Workspace Prices.
 *
 * @since  1.0.0
 */
class Dispatcher extends AbstractModuleDispatcher implements HelperFactoryAwareInterface
{
	use HelperFactoryAwareTrait;

	/**
	 * Returns the layout data.
	 *
	 * @return  array
	 *
	 * @since   1.0.0
	 */
	protected function getLayoutData()
	{
		$data   = parent::getLayoutData();
		$helper = $this->getHelperFactory()->getHelper('CoworkingViewHelper');

		try
		{
			$data['snapshot'] = $helper->getSnapshot($data['params'], $this->getApplication());
		}
		catch (\Throwable $exception)
		{
			unset($exception);

			$data['snapshot'] = RatesParser::failure('unavailable');
		}

		$data['logoUrl'] = Uri::root(true) . '/media/mod_coworkingview/images/logo.png';
		$this->registerStyle();

		return $data;
	}

	/**
	 * Attach the module stylesheet on HTML pages.
	 *
	 * @return  void
	 *
	 * @since   1.0.0
	 */
	private function registerStyle(): void
	{
		$document = $this->getApplication()->getDocument();

		if (!$document instanceof HtmlDocument)
		{
			return;
		}

		$assets   = $document->getWebAssetManager();
		$registry = $assets->getRegistry();

		try
		{
			if (!$registry->exists('style', 'mod_coworkingview'))
			{
				$registry->addExtensionRegistryFile('mod_coworkingview');
			}

			$assets->useStyle('mod_coworkingview');
		}
		catch (\Throwable $exception)
		{
			unset($exception);

			$assets->registerAndUseStyle(
				'mod_coworkingview',
				'mod_coworkingview/css/mod_coworkingview.css',
				['version' => 'auto']
			);
		}
	}
}
