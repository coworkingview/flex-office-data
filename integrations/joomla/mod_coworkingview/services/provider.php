<?php

/**
 * @package     CoworkingView.Site
 * @subpackage  mod_coworkingview
 *
 * @copyright   (C) 2026 CoworkingView
 * @license     GNU General Public License version 2 or later; see LICENSE.txt
 */

// phpcs:disable PSR1.Files.SideEffects
\defined('_JEXEC') or die;
// phpcs:enable PSR1.Files.SideEffects

use Joomla\CMS\Extension\Service\Provider\HelperFactory;
use Joomla\CMS\Extension\Service\Provider\Module;
use Joomla\CMS\Extension\Service\Provider\ModuleDispatcherFactory;
use Joomla\DI\Container;
use Joomla\DI\ServiceProviderInterface;

/**
 * Service provider for CoworkingView Workspace Prices.
 *
 * @since  1.0.0
 */
return new class implements ServiceProviderInterface {
	/**
	 * Registers the service provider with a DI container.
	 *
	 * @param   Container  $container  The DI container.
	 *
	 * @return  void
	 *
	 * @since   1.0.0
	 */
	public function register(Container $container)
	{
		$container->registerServiceProvider(new ModuleDispatcherFactory('\\CoworkingView\\Module\\CoworkingView'));
		$container->registerServiceProvider(new HelperFactory('\\CoworkingView\\Module\\CoworkingView\\Site\\Helper'));
		$container->registerServiceProvider(new Module);
	}
};
