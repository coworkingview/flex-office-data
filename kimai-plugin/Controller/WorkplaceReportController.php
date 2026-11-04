<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\Controller;

use App\Controller\AbstractController;
use App\Form\Model\DateRange;
use App\Utils\PageSetup;
use KimaiPlugin\CoworkingViewBundle\Form\WorkplaceReportForm;
use KimaiPlugin\CoworkingViewBundle\Model\WorkplaceReportQuery;
use KimaiPlugin\CoworkingViewBundle\Reporting\WorkplaceReportBuilder;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route(path: '/reporting/workplace', name: 'coworkingview_workplace_report', methods: ['GET'])]
#[IsGranted('view_reporting')]
final class WorkplaceReportController extends AbstractController
{
    public function __invoke(Request $request, WorkplaceReportBuilder $builder): Response
    {
        $user = $this->getUser();
        $dateFactory = $this->getDateTimeFactory();
        $canFilterUser = $this->isGranted('view_other_timesheet');

        $range = new DateRange(true);
        $range->setBegin($dateFactory->getStartOfMonth());
        $range->setEnd($dateFactory->getEndOfMonth($range->getBegin()));

        $query = new WorkplaceReportQuery();
        $query->setDateRange($range);

        $form = $this->createFormForGetRequest(WorkplaceReportForm::class, $query, [
            'include_user' => $canFilterUser,
            'user' => $user,
        ]);
        $form->submit($request->query->all(), false);

        $totals = $builder->build($user, $query, $canFilterUser);

        $page = new PageSetup('coworkingview.report_title');
        $page->setTranslationDomain('messages');

        return $this->render('@CoworkingView/report/workplace.html.twig', [
            'page_setup' => $page,
            'report_title' => 'coworkingview.report_title',
            'form' => $form->createView(),
            'rows' => $totals->rows(),
            'total_seconds' => $totals->totalSeconds(),
            'total_entries' => $totals->totalEntries(),
        ]);
    }
}
