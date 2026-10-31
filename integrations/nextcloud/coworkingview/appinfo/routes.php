<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

return [
	'routes' => [
		['name' => 'api#cities', 'url' => '/api/cities', 'verb' => 'GET'],
		['name' => 'api#workspaces', 'url' => '/api/workspaces', 'verb' => 'GET'],
	],
];
