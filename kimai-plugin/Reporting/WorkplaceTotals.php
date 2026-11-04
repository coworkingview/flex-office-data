<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\Reporting;

final class WorkplaceTotals
{
    /**
     * @param array<string, array{seconds: int, entries: int}> $byWorkplace
     */
    private function __construct(private readonly array $byWorkplace)
    {
    }

    /**
     * @param list<array{workplace: string, seconds: int}> $rows
     */
    public static function fromRows(array $rows): self
    {
        $byWorkplace = [];
        foreach (Workplace::REPORT_ORDER as $workplace) {
            $byWorkplace[$workplace] = ['seconds' => 0, 'entries' => 0];
        }

        foreach ($rows as $row) {
            $workplace = Workplace::normalize($row['workplace']);
            $byWorkplace[$workplace]['seconds'] += $row['seconds'];
            $byWorkplace[$workplace]['entries']++;
        }

        return new self($byWorkplace);
    }

    /**
     * @return list<array{key: string, label: string, seconds: int, entries: int}>
     */
    public function rows(): array
    {
        $rows = [];
        foreach (Workplace::REPORT_ORDER as $workplace) {
            $rows[] = [
                'key' => $workplace,
                'label' => Workplace::labelKey($workplace),
                'seconds' => $this->byWorkplace[$workplace]['seconds'],
                'entries' => $this->byWorkplace[$workplace]['entries'],
            ];
        }

        return $rows;
    }

    public function totalSeconds(): int
    {
        $total = 0;
        foreach ($this->byWorkplace as $row) {
            $total += $row['seconds'];
        }

        return $total;
    }

    public function totalEntries(): int
    {
        $total = 0;
        foreach ($this->byWorkplace as $row) {
            $total += $row['entries'];
        }

        return $total;
    }
}
