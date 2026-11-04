<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\Reporting;

/**
 * Workplace stored on a timesheet or a project.
 *
 * The meta-field name is within Kimai's 2–50 character limit.
 * Values are stable keys. Labels live in the translation file.
 */
final class Workplace
{
    public const META_NAME = 'workplace';

    public const HOME = 'home';
    public const OFFICE = 'office';
    public const COWORKING = 'coworking';

    /**
     * Shown when neither the timesheet nor the project has a workplace.
     * Not stored. The form submits null instead of this value.
     */
    public const UNSET = '';

    public const VALUES = [
        self::HOME,
        self::OFFICE,
        self::COWORKING,
    ];

    /**
     * Display order, including rows that have no hours.
     *
     * @var list<string>
     */
    public const REPORT_ORDER = [
        self::HOME,
        self::OFFICE,
        self::COWORKING,
        self::UNSET,
    ];

    public static function normalize(mixed $value): string
    {
        if (!is_string($value)) {
            return self::UNSET;
        }

        $value = strtolower(trim($value));
        if (!in_array($value, self::VALUES, true)) {
            return self::UNSET;
        }

        return $value;
    }

    public static function labelKey(string $workplace): string
    {
        return match ($workplace) {
            self::HOME => 'coworkingview.home',
            self::OFFICE => 'coworkingview.office',
            self::COWORKING => 'coworkingview.coworking',
            default => 'coworkingview.unset',
        };
    }
}
