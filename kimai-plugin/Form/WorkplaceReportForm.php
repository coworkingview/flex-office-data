<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 */

namespace KimaiPlugin\CoworkingViewBundle\Form;

use App\Form\Type\DateRangeType;
use App\Form\Type\UserType;
use KimaiPlugin\CoworkingViewBundle\Model\WorkplaceReportQuery;
use Symfony\Component\Form\AbstractType;
use Symfony\Component\Form\FormBuilderInterface;
use Symfony\Component\OptionsResolver\OptionsResolver;

/**
 * @extends AbstractType<WorkplaceReportQuery>
 */
final class WorkplaceReportForm extends AbstractType
{
    public function buildForm(FormBuilderInterface $builder, array $options): void
    {
        $builder->add('dateRange', DateRangeType::class, [
            'label' => false,
            'required' => false,
        ]);

        if ($options['include_user'] === true) {
            $builder->add('user', UserType::class, [
                'label' => false,
                'required' => false,
                'placeholder' => 'coworkingview.all_users',
            ]);
        }
    }

    public function configureOptions(OptionsResolver $resolver): void
    {
        $resolver->setDefaults([
            'data_class' => WorkplaceReportQuery::class,
            'csrf_protection' => false,
            'method' => 'GET',
            'include_user' => false,
            'allow_extra_fields' => true,
        ]);
        $resolver->setAllowedTypes('include_user', 'bool');
    }
}
