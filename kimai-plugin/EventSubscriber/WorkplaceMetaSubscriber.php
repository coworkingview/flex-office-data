<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\EventSubscriber;

use App\Entity\MetaTableTypeInterface;
use App\Entity\ProjectMeta;
use App\Entity\TimesheetMeta;
use App\Event\ProjectMetaDefinitionEvent;
use App\Event\ProjectMetaDisplayEvent;
use App\Event\QuickEntryMetaDisplayEvent;
use App\Event\TimesheetMetaDefinitionEvent;
use App\Event\TimesheetMetaDisplayEvent;
use KimaiPlugin\CoworkingViewBundle\Reporting\Workplace;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\Form\Extension\Core\Type\ChoiceType;
use Symfony\Component\Validator\Constraints\Choice;

/**
 * Registers the workplace field on timesheets and projects.
 *
 * Definition events add it to the create and edit forms.
 * Display events add the column to tables, exports, and quick entry.
 */
final class WorkplaceMetaSubscriber implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            TimesheetMetaDefinitionEvent::class => ['onTimesheetDefinition', 200],
            ProjectMetaDefinitionEvent::class => ['onProjectDefinition', 200],
            TimesheetMetaDisplayEvent::class => ['onTimesheetDisplay', 200],
            QuickEntryMetaDisplayEvent::class => ['onTimesheetDisplay', 200],
            ProjectMetaDisplayEvent::class => ['onProjectDisplay', 200],
        ];
    }

    public function onTimesheetDefinition(TimesheetMetaDefinitionEvent $event): void
    {
        $event->getEntity()->setMetaField($this->field(new TimesheetMeta(), 'coworkingview.help_timesheet'));
    }

    public function onProjectDefinition(ProjectMetaDefinitionEvent $event): void
    {
        $event->getEntity()->setMetaField($this->field(new ProjectMeta(), 'coworkingview.help_project'));
    }

    public function onTimesheetDisplay(TimesheetMetaDisplayEvent|QuickEntryMetaDisplayEvent $event): void
    {
        $event->addField($this->field(new TimesheetMeta(), 'coworkingview.help_timesheet'));
    }

    public function onProjectDisplay(ProjectMetaDisplayEvent $event): void
    {
        $event->addField($this->field(new ProjectMeta(), 'coworkingview.help_project'));
    }

    private function field(MetaTableTypeInterface $definition, string $help): MetaTableTypeInterface
    {
        $definition
            ->setName(Workplace::META_NAME)
            ->setLabel('coworkingview.workplace')
            ->setType(ChoiceType::class)
            ->setIsVisible(true)
            ->setIsRequired(false)
            ->setOrder(100)
            ->setOptions([
                'help' => $help,
                'placeholder' => 'coworkingview.unset',
                'choices' => [
                    'coworkingview.home' => Workplace::HOME,
                    'coworkingview.office' => Workplace::OFFICE,
                    'coworkingview.coworking' => Workplace::COWORKING,
                ],
            ])
            ->addConstraint(new Choice(['choices' => Workplace::VALUES]));

        return $definition;
    }
}
