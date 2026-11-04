<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\Reporting;

use App\Entity\User;
use App\Repository\Query\TimesheetQuery;
use App\Repository\TimesheetRepository;
use KimaiPlugin\CoworkingViewBundle\Model\WorkplaceReportQuery;

/**
 * Loads the timesheets Kimai already allows this user to see and groups them.
 *
 * A timesheet counts in the range of its start, which is the same rule as the
 * timesheet screen. A running entry counts the duration up to now.
 */
final class WorkplaceReportBuilder
{
    public function __construct(private readonly TimesheetRepository $repository)
    {
    }

    public function build(User $viewer, WorkplaceReportQuery $query, bool $canFilterUser): WorkplaceTotals
    {
        $timesheetQuery = new TimesheetQuery();
        $timesheetQuery->setCurrentUser($viewer);

        $range = $query->getDateRange();
        if ($range !== null && $range->getBegin() !== null) {
            $timesheetQuery->setBegin($range->getBegin());
        }
        if ($range !== null && $range->getEnd() !== null) {
            $timesheetQuery->setEnd($range->getEnd());
        }
        if ($canFilterUser && $query->getUser() instanceof User) {
            $timesheetQuery->setUser($query->getUser());
        }

        $rows = [];
        foreach ($this->repository->getTimesheetResult($timesheetQuery)->getResults() as $timesheet) {
            $timesheetMeta = $timesheet->getMetaField(Workplace::META_NAME);
            $project = $timesheet->getProject();
            $projectMeta = $project?->getMetaField(Workplace::META_NAME);
            $duration = $timesheet->getDuration();

            $rows[] = [
                'workplace' => WorkplaceResolver::resolve(
                    $timesheetMeta?->getValue(),
                    $projectMeta?->getValue()
                ),
                'seconds' => $duration ?? 0,
            ];
        }

        return WorkplaceTotals::fromRows($rows);
    }
}
