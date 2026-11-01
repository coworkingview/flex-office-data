// Copyright (c) 2026 CoworkingView. License: MIT.
module coworkingview.check;

import std.algorithm.searching : canFind;
import std.conv : to;
import std.math : isFinite;
import std.string : strip;
import std.typecons : Nullable;
import std.uni : toUpper;

import coworkingview.error : CoworkingViewException;
import coworkingview.jsonutil : decimalText;

package immutable string[] locales = ["en", "es", "de"];
package immutable string[] currencies = ["EUR", "GBP", "USD", "CHF", "AED", "VES"];
package immutable string[] products = [
    "flex_desk", "fix_desk", "private_office", "exclusive_bereich", "day_pass",
    "meeting_room", "event_space", "virtual_office", "membership"
];
package immutable string[] sorts = ["random", "price-asc", "date-desc", "date-asc"];
package enum maxSpaces = 200;

package string checkLocale(string value)
{
    return oneOf("locale", value, locales);
}

package string checkCurrency(string value)
{
    if (value is null)
        return null;
    return oneOf("currency", value.toUpper, currencies);
}

package string checkProduct(string value)
{
    if (value is null)
        return null;
    return oneOf("product", value, products);
}

package string checkSort(string value)
{
    return oneOf("sort", value, sorts);
}

package string checkText(string name, string value)
{
    if (value is null)
        return null;
    auto trimmed = value.strip;
    if (trimmed.length == 0)
    {
        throw new CoworkingViewException(
            name ~ " must be a non-empty string, got '" ~ value ~ "'.");
    }
    return trimmed;
}

package int checkLimit(int value)
{
    if (value < 1)
    {
        throw new CoworkingViewException(
            "limit must be a positive integer, got " ~ to!string(value) ~ ".");
    }
    if (value > maxSpaces)
    {
        throw new CoworkingViewException(
            "limit=" ~ to!string(value) ~ " exceeds the maximum of " ~ to!string(maxSpaces)
            ~ ". The catalogue may be searched and linked to, not bulk-copied: its content belongs to the operators "
            ~ "and the API's catalogue notice forbids systematic extraction. Narrow the "
            ~ "search (city, zone, operator, product, price) instead.");
    }
    return value;
}

package Nullable!long checkCount(string name, Nullable!long value)
{
    if (value.isNull)
        return value;
    if (value.get < 0)
    {
        throw new CoworkingViewException(
            name ~ " must be a non-negative integer, got " ~ to!string(value.get) ~ ".");
    }
    return value;
}

package Nullable!double checkPrice(string name, Nullable!double value)
{
    if (value.isNull)
        return value;
    auto number = value.get;
    if (!isFinite(number) || number < 0)
    {
        throw new CoworkingViewException(
            name ~ " must be a non-negative number, got " ~ to!string(number) ~ ".");
    }
    return value;
}

package void checkPriceRange(Nullable!double minPrice, Nullable!double maxPrice)
{
    if (!minPrice.isNull && !maxPrice.isNull && minPrice.get > maxPrice.get)
    {
        throw new CoworkingViewException(
            "min_price (" ~ decimalText(minPrice.get) ~ ") is greater than max_price ("
            ~ decimalText(maxPrice.get) ~ ").");
    }
}

package string checkSlug(string value)
{
    import std.ascii : isAlphaNum;

    bool ok = value.length > 0;
    foreach (i, c; value)
    {
        if (c > 127 || (i == 0 ? !isAlphaNum(c) : !(isAlphaNum(c) || c == '.' || c == '_' || c == '-')))
        {
            ok = false;
            break;
        }
    }
    if (!ok)
    {
        throw new CoworkingViewException(
            "slug='" ~ value ~ "' is not a valid slug; slugs are letters, digits, '.', '_' "
            ~ "and '-', starting with a letter or digit (e.g. 'sankt-oberholz-rosenthaler-berlin').");
    }
    return value;
}

package double checkTimeout(double value)
{
    if (!isFinite(value) || value <= 0)
    {
        throw new CoworkingViewException(
            "timeout must be a positive number of seconds, got " ~ to!string(value) ~ ".");
    }
    return value;
}

private string oneOf(string name, string value, immutable(string)[] valid)
{
    if (canFind(valid, value))
        return value;
    string choices;
    foreach (i, item; valid)
    {
        if (i)
            choices ~= ", ";
        choices ~= "'" ~ item ~ "'";
    }
    throw new CoworkingViewException(
        name ~ "='" ~ value ~ "' is not supported; use one of " ~ choices ~ ".");
}
