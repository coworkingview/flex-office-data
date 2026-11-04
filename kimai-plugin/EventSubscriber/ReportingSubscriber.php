<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\EventSubscriber;

use App\Event\ReportingEvent;
use App\Reporting\Report;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

final class ReportingSubscriber implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            ReportingEvent::class => ['onReporting', 100],
        ];
    }

    public function onReporting(ReportingEvent $event): void
    {
        $event->addReport(new Report(
            'coworkingview_workplace',
            'coworkingview_workplace_report',
            'coworkingview.report_title',
            'building',
            'messages'
        ));
    }
}
