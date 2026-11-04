<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\Tests;

use KimaiPlugin\CoworkingViewBundle\Reporting\Workplace;
use KimaiPlugin\CoworkingViewBundle\Reporting\WorkplaceResolver;
use KimaiPlugin\CoworkingViewBundle\Reporting\WorkplaceTotals;
use PHPUnit\Framework\TestCase;

final class WorkplaceTest extends TestCase
{
    public function testMetaNameFitsKimaiColumn(): void
    {
        $length = strlen(Workplace::META_NAME);

        self::assertGreaterThanOrEqual(2, $length);
        self::assertLessThanOrEqual(50, $length);
        self::assertSame(strtolower(Workplace::META_NAME), Workplace::META_NAME);
    }

    public function testNormalizeAcceptsKnownValuesInAnyCase(): void
    {
        self::assertSame(Workplace::HOME, Workplace::normalize(' Home '));
        self::assertSame(Workplace::OFFICE, Workplace::normalize('OFFICE'));
        self::assertSame(Workplace::COWORKING, Workplace::normalize('coworking'));
    }

    public function testNormalizeDropsUnknownValues(): void
    {
        self::assertSame(Workplace::UNSET, Workplace::normalize(null));
        self::assertSame(Workplace::UNSET, Workplace::normalize(''));
        self::assertSame(Workplace::UNSET, Workplace::normalize('   '));
        self::assertSame(Workplace::UNSET, Workplace::normalize('cafe'));
        self::assertSame(Workplace::UNSET, Workplace::normalize(12));
    }

    public function testTimesheetWorkplaceWinsOverProject(): void
    {
        self::assertSame(
            Workplace::HOME,
            WorkplaceResolver::resolve(Workplace::HOME, Workplace::OFFICE)
        );
    }

    public function testProjectWorkplaceIsTheFallback(): void
    {
        self::assertSame(
            Workplace::COWORKING,
            WorkplaceResolver::resolve(null, ' Coworking ')
        );
        self::assertSame(
            Workplace::OFFICE,
            WorkplaceResolver::resolve('somewhere else', Workplace::OFFICE)
        );
    }

    public function testMissingBothIsUnset(): void
    {
        self::assertSame(Workplace::UNSET, WorkplaceResolver::resolve(null, null));
        self::assertSame(Workplace::UNSET, WorkplaceResolver::resolve('', 'nope'));
    }

    public function testTotalsKeepAStableOrderAndSumHours(): void
    {
        $totals = WorkplaceTotals::fromRows([
            ['workplace' => Workplace::HOME, 'seconds' => 3600],
            ['workplace' => 'home', 'seconds' => 1800],
            ['workplace' => Workplace::COWORKING, 'seconds' => 90],
            ['workplace' => 'unknown', 'seconds' => 30],
            ['workplace' => Workplace::UNSET, 'seconds' => 15],
        ]);

        $keys = array_map(static fn (array $row): string => $row['key'], $totals->rows());

        self::assertSame(Workplace::REPORT_ORDER, $keys);
        self::assertSame(
            [
                'coworkingview.home',
                'coworkingview.office',
                'coworkingview.coworking',
                'coworkingview.unset',
            ],
            array_map(static fn (array $row): string => $row['label'], $totals->rows())
        );

        $byKey = [];
        foreach ($totals->rows() as $row) {
            $byKey[$row['key']] = $row;
        }

        self::assertSame(5400, $byKey[Workplace::HOME]['seconds']);
        self::assertSame(2, $byKey[Workplace::HOME]['entries']);
        self::assertSame(0, $byKey[Workplace::OFFICE]['seconds']);
        self::assertSame(0, $byKey[Workplace::OFFICE]['entries']);
        self::assertSame(90, $byKey[Workplace::COWORKING]['seconds']);
        self::assertSame(1, $byKey[Workplace::COWORKING]['entries']);
        self::assertSame(45, $byKey[Workplace::UNSET]['seconds']);
        self::assertSame(2, $byKey[Workplace::UNSET]['entries']);
        self::assertSame(5535, $totals->totalSeconds());
        self::assertSame(5, $totals->totalEntries());
    }

    public function testEmptyReportStillListsEveryWorkplace(): void
    {
        $totals = WorkplaceTotals::fromRows([]);

        self::assertCount(4, $totals->rows());
        self::assertSame(0, $totals->totalSeconds());
        self::assertSame(0, $totals->totalEntries());
    }
}
