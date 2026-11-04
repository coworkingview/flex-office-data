<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\Reporting;

/**
 * A workplace on the timesheet wins. The project workplace is the fallback.
 */
final class WorkplaceResolver
{
    public static function resolve(mixed $timesheetValue, mixed $projectValue): string
    {
        $timesheet = Workplace::normalize($timesheetValue);
        if ($timesheet !== Workplace::UNSET) {
            return $timesheet;
        }

        return Workplace::normalize($projectValue);
    }
}
