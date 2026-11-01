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

use CoworkingView\Module\CoworkingView\Site\Helper\RatesParser;
use Joomla\CMS\Language\Text;

$snapshot = isset($snapshot) && is_array($snapshot) ? $snapshot : RatesParser::failure('unavailable');
$moduleId = 0;

if (isset($module) && is_object($module) && isset($module->id)) {
	$moduleId = (int) $module->id;
}

$headingId = 'mod-coworkingview-title-' . $moduleId;
$cityName  = isset($snapshot['cityName']) && is_string($snapshot['cityName']) ? $snapshot['cityName'] : '';
$heading   = $cityName !== '' ? $cityName : Text::_('MOD_COWORKINGVIEW_HEADING');
$currency  = isset($snapshot['currency']) && is_string($snapshot['currency']) ? $snapshot['currency'] : '';
$rows      = isset($snapshot['rows']) && is_array($snapshot['rows']) ? $snapshot['rows'] : [];
$ok        = ($snapshot['ok'] ?? false) === true;
$code      = isset($snapshot['code']) && is_string($snapshot['code']) ? $snapshot['code'] : 'unavailable';
$logo      = isset($logoUrl) && is_string($logoUrl) ? $logoUrl : '';

$products = [
	'flex_desk'          => Text::_('MOD_COWORKINGVIEW_PRODUCT_FLEX_DESK'),
	'fix_desk'           => Text::_('MOD_COWORKINGVIEW_PRODUCT_FIX_DESK'),
	'private_office'     => Text::_('MOD_COWORKINGVIEW_PRODUCT_PRIVATE_OFFICE'),
	'exclusive_bereich'  => Text::_('MOD_COWORKINGVIEW_PRODUCT_EXCLUSIVE_BEREICH'),
	'day_pass'           => Text::_('MOD_COWORKINGVIEW_PRODUCT_DAY_PASS'),
	'meeting_room'       => Text::_('MOD_COWORKINGVIEW_PRODUCT_MEETING_ROOM'),
	'event_space'        => Text::_('MOD_COWORKINGVIEW_PRODUCT_EVENT_SPACE'),
	'virtual_office'     => Text::_('MOD_COWORKINGVIEW_PRODUCT_VIRTUAL_OFFICE'),
	'membership'         => Text::_('MOD_COWORKINGVIEW_PRODUCT_MEMBERSHIP'),
];

$units = [
	'month' => Text::_('MOD_COWORKINGVIEW_UNIT_MONTH'),
	'day'   => Text::_('MOD_COWORKINGVIEW_UNIT_DAY'),
	'hour'  => Text::_('MOD_COWORKINGVIEW_UNIT_HOUR'),
];

$errors = [
	'bad_city'     => Text::_('MOD_COWORKINGVIEW_ERROR_CITY'),
	'bad_product'  => Text::_('MOD_COWORKINGVIEW_ERROR_PRODUCT'),
	'unavailable'  => Text::_('MOD_COWORKINGVIEW_ERROR_UNAVAILABLE'),
	'bad_response' => Text::_('MOD_COWORKINGVIEW_ERROR_RESPONSE'),
	'unpublished'  => Text::_('MOD_COWORKINGVIEW_ERROR_UNPUBLISHED'),
	'unknown_city' => Text::_('MOD_COWORKINGVIEW_ERROR_UNKNOWN_CITY'),
];

$sectionClass = 'mod-coworkingview' . ($ok ? '' : ' mod-coworkingview--error');
$dash         = Text::_('MOD_COWORKINGVIEW_EMPTY');
$licenseUrl   = RatesParser::httpsUrl(
	isset($snapshot['licenseUrl']) && is_string($snapshot['licenseUrl']) ? $snapshot['licenseUrl'] : null
);
$licenseName = isset($snapshot['license']) && is_string($snapshot['license']) ? $snapshot['license'] : '';
$asOf        = isset($snapshot['asOfLabel']) && is_string($snapshot['asOfLabel']) ? $snapshot['asOfLabel'] : '';
$credit      = isset($snapshot['attribution']) && is_string($snapshot['attribution']) ? $snapshot['attribution'] : '';
$detail      = isset($snapshot['detail']) && is_string($snapshot['detail']) ? $snapshot['detail'] : '';
$status      = isset($snapshot['status']) && is_int($snapshot['status']) ? $snapshot['status'] : 0;

?>
<section class="<?php echo htmlspecialchars($sectionClass, ENT_QUOTES, 'UTF-8'); ?>" aria-labelledby="<?php echo htmlspecialchars($headingId, ENT_QUOTES, 'UTF-8'); ?>">
	<div class="mod-coworkingview__mast">
		<?php if ($logo !== '') : ?>
			<a class="mod-coworkingview__mark" href="https://coworkingview.com">
				<img
					src="<?php echo htmlspecialchars($logo, ENT_QUOTES, 'UTF-8'); ?>"
					alt="<?php echo htmlspecialchars(Text::_('MOD_COWORKINGVIEW_LOGO_ALT'), ENT_QUOTES, 'UTF-8'); ?>"
					width="36"
					height="36"
				>
			</a>
		<?php endif; ?>
		<div class="mod-coworkingview__heading">
			<h2 id="<?php echo htmlspecialchars($headingId, ENT_QUOTES, 'UTF-8'); ?>" class="mod-coworkingview__title">
				<?php echo htmlspecialchars($heading, ENT_QUOTES, 'UTF-8'); ?>
			</h2>
			<p class="mod-coworkingview__kicker"><?php echo htmlspecialchars(Text::_('MOD_COWORKINGVIEW_HEADING'), ENT_QUOTES, 'UTF-8'); ?></p>
		</div>
	</div>

	<?php if (!$ok) : ?>
		<p class="mod-coworkingview__message" role="status">
			<?php if ($code === 'http' && $status > 0) : ?>
				<?php echo htmlspecialchars(Text::sprintf('MOD_COWORKINGVIEW_ERROR_HTTP', (string) $status), ENT_QUOTES, 'UTF-8'); ?>
			<?php else : ?>
				<?php echo htmlspecialchars($errors[$code] ?? Text::_('MOD_COWORKINGVIEW_ERROR_UNAVAILABLE'), ENT_QUOTES, 'UTF-8'); ?>
			<?php endif; ?>
		</p>
		<?php if ($detail !== '') : ?>
			<p class="mod-coworkingview__detail"><?php echo htmlspecialchars($detail, ENT_QUOTES, 'UTF-8'); ?></p>
		<?php endif; ?>
	<?php elseif ($rows === []) : ?>
		<p class="mod-coworkingview__message" role="status">
			<?php echo htmlspecialchars(Text::_('MOD_COWORKINGVIEW_EMPTY_ROWS'), ENT_QUOTES, 'UTF-8'); ?>
		</p>
	<?php else : ?>
		<table class="mod-coworkingview__table">
			<caption><?php echo htmlspecialchars(Text::sprintf('MOD_COWORKINGVIEW_CAPTION', $currency !== '' ? $currency : $dash), ENT_QUOTES, 'UTF-8'); ?></caption>
			<thead>
				<tr>
					<th scope="col"><?php echo htmlspecialchars(Text::_('MOD_COWORKINGVIEW_COLUMN_PRODUCT'), ENT_QUOTES, 'UTF-8'); ?></th>
					<th scope="col"><?php echo htmlspecialchars(Text::_('MOD_COWORKINGVIEW_COLUMN_MEDIAN'), ENT_QUOTES, 'UTF-8'); ?></th>
					<th scope="col"><?php echo htmlspecialchars(Text::_('MOD_COWORKINGVIEW_COLUMN_SPREAD'), ENT_QUOTES, 'UTF-8'); ?></th>
					<th scope="col"><?php echo htmlspecialchars(Text::_('MOD_COWORKINGVIEW_COLUMN_SAMPLE'), ENT_QUOTES, 'UTF-8'); ?></th>
				</tr>
			</thead>
			<tbody>
				<?php foreach ($rows as $row) : ?>
					<?php
					if (!is_array($row)) {
						continue;
					}

					$product = isset($row['product']) && is_string($row['product']) ? $row['product'] : '';
					$label   = $products[$product] ?? $product;
					$unitKey = isset($row['unit']) && is_string($row['unit']) ? $row['unit'] : '';
					$unit    = $units[$unitKey] ?? '';
					$median  = is_float($row['median'] ?? null) || is_int($row['median'] ?? null)
						? RatesParser::formatMoney((float) $row['median'], isset($row['currency']) && is_string($row['currency']) ? $row['currency'] : $currency)
						: $dash;
					$p25 = is_float($row['p25'] ?? null) || is_int($row['p25'] ?? null)
						? RatesParser::formatAmount((float) $row['p25'])
						: $dash;
					$p75 = is_float($row['p75'] ?? null) || is_int($row['p75'] ?? null)
						? RatesParser::formatAmount((float) $row['p75'])
						: $dash;
					$sample = isset($row['sampleSize']) && is_int($row['sampleSize']) ? (string) $row['sampleSize'] : $dash;
					$low    = ($row['lowConfidence'] ?? false) === true;
					?>
					<tr>
						<th scope="row">
							<?php echo htmlspecialchars($label, ENT_QUOTES, 'UTF-8'); ?>
							<?php if ($unit !== '') : ?>
								<span class="mod-coworkingview__unit"><?php echo htmlspecialchars($unit, ENT_QUOTES, 'UTF-8'); ?></span>
							<?php endif; ?>
						</th>
						<td><?php echo htmlspecialchars($median, ENT_QUOTES, 'UTF-8'); ?></td>
						<td><?php echo htmlspecialchars($p25 . ' – ' . $p75, ENT_QUOTES, 'UTF-8'); ?></td>
						<td>
							<?php echo htmlspecialchars($sample, ENT_QUOTES, 'UTF-8'); ?>
							<?php if ($low) : ?>
								<span class="mod-coworkingview__low"><?php echo htmlspecialchars(Text::_('MOD_COWORKINGVIEW_LOW_CONFIDENCE'), ENT_QUOTES, 'UTF-8'); ?></span>
							<?php endif; ?>
						</td>
					</tr>
				<?php endforeach; ?>
			</tbody>
		</table>
	<?php endif; ?>

	<footer class="mod-coworkingview__foot">
		<?php if ($asOf !== '') : ?>
			<p class="mod-coworkingview__asof"><?php echo htmlspecialchars(Text::sprintf('MOD_COWORKINGVIEW_AS_OF', $asOf), ENT_QUOTES, 'UTF-8'); ?></p>
		<?php endif; ?>
		<?php if ($credit !== '') : ?>
			<p class="mod-coworkingview__note"><?php echo htmlspecialchars($credit, ENT_QUOTES, 'UTF-8'); ?></p>
		<?php endif; ?>
		<p class="mod-coworkingview__credit">
			<a href="https://coworkingview.com"><?php echo htmlspecialchars(Text::_('MOD_COWORKINGVIEW_ATTRIBUTION'), ENT_QUOTES, 'UTF-8'); ?></a>
			<?php if ($licenseUrl !== null) : ?>
				<a href="<?php echo htmlspecialchars($licenseUrl, ENT_QUOTES, 'UTF-8'); ?>"><?php echo htmlspecialchars($licenseName !== '' ? $licenseName : Text::_('MOD_COWORKINGVIEW_LICENSE'), ENT_QUOTES, 'UTF-8'); ?></a>
			<?php endif; ?>
		</p>
	</footer>
</section>
