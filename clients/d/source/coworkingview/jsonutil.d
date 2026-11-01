// Copyright (c) 2026 CoworkingView. License: MIT.
module coworkingview.jsonutil;

import std.conv : to;
import std.json : JSONType, JSONValue, parseJSON;
import std.typecons : Nullable;

import coworkingview.error : ShapeException;

package struct Number
{
    bool present;
    double value;
    string text;
}

package JSONValue field(JSONValue obj, string key)
{
    if (obj.type != JSONType.object)
        return JSONValue.init;
    auto found = key in obj.object;
    if (found is null)
        return JSONValue.init;
    return *found;
}

package JSONValue requireMember(JSONValue obj, string key)
{
    if (obj.type != JSONType.object || (key in obj.object) is null)
        throw new ShapeException("The API response has no '" ~ key ~ "' member");
    return obj.object[key];
}

package string optionalString(JSONValue value)
{
    if (value.type == JSONType.string)
        return value.str;
    return null;
}

package bool isStat(JSONValue value)
{
    if (value.type != JSONType.object)
        return false;
    return ("median" in value.object) !is null && ("sampleSize" in value.object) !is null;
}

package string numberText(JSONValue value)
{
    switch (value.type)
    {
    case JSONType.integer:
        return to!string(value.integer);
    case JSONType.uinteger:
        return to!string(value.uinteger);
    case JSONType.float_:
        return shortestNumber(value.floating);
    default:
        throw new ShapeException("Unexpected shape for a price");
    }
}

package Number readNumber(JSONValue value)
{
    if (value.type == JSONType.null_)
        return Number.init;
    if (value.type != JSONType.integer && value.type != JSONType.uinteger
        && value.type != JSONType.float_)
        throw new ShapeException("Unexpected shape for a price");
    Number number;
    number.present = true;
    number.text = numberText(value);
    number.value = value.type == JSONType.float_ ? value.floating : to!double(number.text);
    return number;
}

/// A money object `{ "amount", "currency" }`. Null and missing are absent.
package Number amount(JSONValue value)
{
    if (value.type == JSONType.null_)
        return Number.init;
    if (value.type != JSONType.object)
        throw new ShapeException("Unexpected shape for a price");
    auto raw = field(value, "amount");
    if (raw.type == JSONType.null_)
        throw new ShapeException("Unexpected shape for a price");
    return readNumber(raw);
}

package Nullable!long readLong(JSONValue value)
{
    if (value.type == JSONType.integer)
        return Nullable!long(value.integer);
    if (value.type == JSONType.uinteger && value.uinteger <= long.max)
        return Nullable!long(cast(long) value.uinteger);
    return Nullable!long.init;
}

package Nullable!bool readBool(JSONValue value)
{
    if (value.type == JSONType.true_)
        return Nullable!bool(true);
    if (value.type == JSONType.false_)
        return Nullable!bool(false);
    return Nullable!bool.init;
}

package string readSeed(JSONValue value)
{
    if (value.type == JSONType.string)
        return value.str;
    if (value.type == JSONType.integer || value.type == JSONType.uinteger
        || value.type == JSONType.float_)
        return numberText(value);
    return null;
}

package string decimalText(double value)
{
    import std.math : abs, isFinite, rndtol;

    if (isFinite(value) && value == rndtol(value) && abs(value) < 1e15)
        return to!string(cast(long) value);
    return shortestNumber(value);
}

package string shortestNumber(double value)
{
    import std.algorithm.searching : canFind;
    import std.format : format;

    string scientific;
    foreach (p; 1 .. 18)
    {
        auto text = format("%.*g", p, value);
        double back;
        try
            back = to!double(text);
        catch (Exception)
            continue;
        if (back != value)
            continue;
        if (canFind(text, 'e') || canFind(text, 'E'))
        {
            if (scientific is null)
                scientific = text;
            continue;
        }
        return text;
    }
    if (scientific !is null)
        return scientific;
    return format("%.17g", value);
}

package Nullable!double asDouble(Number number)
{
    if (!number.present)
        return Nullable!double.init;
    return Nullable!double(number.value);
}

unittest
{
    auto parsed = parseJSON(
        `{"a":13.318559,"b":13.4018374,"c":52.5294539,"d":52.5476944,"e":52.501028,"f":13.2194038,"g":12.5,"h":100}`);
    assert(numberText(parsed["a"]) == "13.318559");
    assert(numberText(parsed["b"]) == "13.4018374");
    assert(numberText(parsed["c"]) == "52.5294539");
    assert(numberText(parsed["d"]) == "52.5476944");
    assert(numberText(parsed["e"]) == "52.501028");
    assert(numberText(parsed["f"]) == "13.2194038");
    assert(numberText(parsed["g"]) == "12.5");
    assert(numberText(parsed["h"]) == "100");
    assert(decimalText(10) == "10");
    assert(decimalText(99.5) == "99.5");
}
