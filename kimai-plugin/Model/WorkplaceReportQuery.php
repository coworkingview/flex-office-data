<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\Model;

use App\Entity\User;
use App\Form\Model\DateRange;

final class WorkplaceReportQuery
{
    private ?DateRange $dateRange = null;
    private ?User $user = null;

    public function getDateRange(): ?DateRange
    {
        return $this->dateRange;
    }

    public function setDateRange(?DateRange $dateRange): void
    {
        $this->dateRange = $dateRange;
    }

    public function getUser(): ?User
    {
        return $this->user;
    }

    public function setUser(?User $user): void
    {
        $this->user = $user;
    }
}
