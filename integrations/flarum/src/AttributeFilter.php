<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices;

/**
 * s9e attribute filters. Static methods so the cached parser can serialize them.
 */
final class AttributeFilter
{
    public static function city(mixed $value): string|false
    {
        if (!is_string($value)) {
            return false;
        }

        $value = strtolower(trim($value));

        if (strlen($value) > 64 || preg_match('/\A[a-z0-9][a-z0-9._-]*\z/', $value) !== 1) {
            return false;
        }

        return $value;
    }

    public static function product(mixed $value): string|false
    {
        if (!is_string($value)) {
            return false;
        }

        $value = strtolower(trim($value));

        if ($value === '' || $value === 'all') {
            return false;
        }

        if (strlen($value) > 64 || preg_match('/\A[a-z0-9][a-z0-9_-]*\z/', $value) !== 1) {
            return false;
        }

        return $value;
    }

    public static function locale(mixed $value): string|false
    {
        if (!is_string($value)) {
            return false;
        }

        $value = strtolower(trim($value));

        return in_array($value, ['en', 'de', 'es'], true) ? $value : false;
    }

    /**
     * Forum serializer: the sidebar is on unless an admin saved it as off.
     */
    public static function showWidget(mixed $value): bool
    {
        if ($value === null || $value === '') {
            return true;
        }

        return !in_array($value, [false, 0, '0', 'false'], true);
    }
}
