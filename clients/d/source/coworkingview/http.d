// Copyright (c) 2026 CoworkingView. License: MIT.
module coworkingview.http;

import std.algorithm.searching : canFind, findSplit;
import std.array : appender;
import std.conv : to;
import std.datetime.date : DateTime;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.json : JSONException, JSONType, JSONValue, parseJSON;
import std.string : indexOf, strip, toLower;
import std.typecons : Nullable;
import std.uri : encodeComponent;

import coworkingview.error : APIException, FieldError;
import coworkingview.jsonutil : field, optionalString;

/// One HTTP response. `status` is the HTTP status, not a status copied from the body.
struct HTTPResult
{
    int status;
    string reason;
    string[string] headers;
    string body;
}

/// One GET. Throw on a connection failure; do not throw for an HTTP error status.
interface Transport
{
    HTTPResult get(string url, string[string] headers, double timeoutSeconds);
}

/// The single retry delay. Tests replace it so they do not sleep.
interface Sleeper
{
    void sleepSeconds(double seconds);
}

/// `std.net.curl` transport. Nothing is sent until `get` is called.
class CurlTransport : Transport
{
    override HTTPResult get(string url, string[string] headers, double timeoutSeconds)
    {
        import core.time : dur;
        import std.net.curl : CurlException, HTTP;

        auto http = HTTP(url);
        http.method = HTTP.Method.get;
        foreach (name, value; headers)
            http.addRequestHeader(name, value);
        long msecs = cast(long) (timeoutSeconds * 1000.0);
        if (msecs < 1)
            msecs = 1;
        auto budget = dur!"msecs"(msecs);
        http.operationTimeout = budget;
        http.connectTimeout = budget;
        if (timeoutSeconds >= 1)
            http.dataTimeout = budget;

        auto collected = appender!(ubyte[])();
        http.onReceive = (ubyte[] data) {
            collected.put(data);
            return data.length;
        };
        try
            http.perform();
        catch (CurlException e)
            throw e;

        auto code = cast(int) http.statusLine.code;
        auto reason = http.statusLine.reason;
        if (reason.length == 0)
            reason = reasonPhrase(code);
        string body = cast(string) collected.data.idup;
        return HTTPResult(code, reason, http.responseHeaders.dup, body);
    }
}

/// Sleeps the calling thread. Used by the default client.
class ThreadSleeper : Sleeper
{
    override void sleepSeconds(double seconds)
    {
        import core.thread : Thread;
        import core.time : dur;

        if (seconds <= 0)
            return;
        Thread.sleep(dur!"msecs"(cast(long) (seconds * 1000.0)));
    }
}

package string buildURL(string base, string path, string[2][] query)
{
    auto built = appender!string();
    built.put(base);
    built.put(path);
    if (query.length == 0)
        return built.data;
    built.put("?");
    foreach (i, pair; query)
    {
        if (i)
            built.put("&");
        built.put(encodeComponent(pair[0]));
        built.put("=");
        built.put(encodeComponent(pair[1]));
    }
    return built.data;
}

package bool isRetryable(int status)
{
    return status == 429 || (status >= 500 && status <= 599);
}

package string headerValue(string[string] headers, string name)
{
    auto want = name.toLower;
    foreach (key, value; headers)
    {
        if (key.toLower == want)
            return value;
    }
    return null;
}

package double retryWait(string[string] headers)
{
    return retryWait(headers, Clock.currTime(UTC()));
}

package double retryWait(string[string] headers, SysTime now)
{
    enum fallback = 2.0;
    enum maximum = 10.0;
    auto retry = delayOf(headerValue(headers, "Retry-After"), now);
    Nullable!double chosen = retry;
    if (chosen.isNull)
        chosen = delayOf(headerValue(headers, "RateLimit-Reset"), now);
    double wait = chosen.isNull ? fallback : chosen.get;
    if (wait < 0)
        wait = 0;
    if (wait > maximum)
        wait = maximum;
    return wait;
}

package string reasonPhrase(int status)
{
    switch (status)
    {
    case 200:
        return "OK";
    case 400:
        return "Bad Request";
    case 401:
        return "Unauthorized";
    case 403:
        return "Forbidden";
    case 404:
        return "Not Found";
    case 409:
        return "Conflict";
    case 422:
        return "Unprocessable Entity";
    case 429:
        return "Too Many Requests";
    case 500:
        return "Internal Server Error";
    case 502:
        return "Bad Gateway";
    case 503:
        return "Service Unavailable";
    case 504:
        return "Gateway Timeout";
    default:
        return "HTTP " ~ to!string(status);
    }
}

package JSONValue parseSuccessBody(HTTPResult response, string path)
{
    JSONValue value;
    try
        value = parseJSON(response.body);
    catch (JSONException)
    {
        throw new APIException(response.status, "BAD_RESPONSE",
            "The API returned a body that is not valid JSON", httpDetail(response));
    }
    if (value.type != JSONType.object)
    {
        throw new APIException(response.status, "BAD_RESPONSE",
            "The API returned JSON that is not an object", "GET " ~ path);
    }
    return value;
}

package APIException problemOf(HTTPResult response)
{
    JSONValue body;
    bool parsed;
    try
    {
        if (response.body.length)
        {
            body = parseJSON(response.body);
            parsed = true;
        }
    }
    catch (JSONException)
    {
        parsed = false;
    }
    string title;
    string detail;
    string code;
    FieldError[] errors;
    if (parsed && body.type == JSONType.object)
    {
        title = optionalString(field(body, "title"));
        detail = optionalString(field(body, "detail"));
        code = optionalString(field(body, "code"));
        auto rawErrors = field(body, "errors");
        if (rawErrors.type == JSONType.array)
        {
            foreach (item; rawErrors.array)
            {
                if (item.type != JSONType.object)
                    continue;
                errors ~= FieldError(optionalString(field(item, "path")),
                    optionalString(field(item, "message")));
            }
        }
    }
    if (code.length == 0)
        code = "HTTP_" ~ to!string(response.status);
    if (title.length == 0)
    {
        auto reason = response.reason.strip;
        title = reason.length ? reason : "HTTP " ~ to!string(response.status);
    }
    return new APIException(response.status, code, title, detail, errors);
}

private string httpDetail(HTTPResult response)
{
    auto text = "HTTP " ~ to!string(response.status);
    auto reason = response.reason.strip;
    if (reason.length)
        text ~= " " ~ reason;
    return text;
}

private Nullable!double delayOf(string raw, SysTime now)
{
    if (raw is null)
        return Nullable!double.init;
    auto text = raw.strip;
    if (text.length == 0)
        return Nullable!double.init;
    try
    {
        auto number = to!double(text);
        if (number < 0)
            number = 0;
        return Nullable!double(number);
    }
    catch (Exception)
    {
    }
    SysTime when;
    if (!parseHTTPDate(text, when))
        return Nullable!double.init;
    auto seconds = (when - now).total!"usecs" / 1_000_000.0;
    if (seconds < 0)
        seconds = 0;
    return Nullable!double(seconds);
}

package bool parseHTTPDate(string text, out SysTime result)
{
    import std.algorithm : splitter;

    string[] tokens;
    foreach (part; text.strip.splitter(' '))
    {
        if (part.length)
            tokens ~= part.idup;
    }
    if (tokens.length >= 4 && tokens[0].length && tokens[0][$ - 1] == ',')
    {
        if (canFind(tokens[1], '-'))
            return parseRFC850(tokens, result);
        return parseIMF(tokens, result);
    }
    if (tokens.length == 5)
        return parseAsctime(tokens, result);
    return false;
}

private bool parseIMF(string[] tokens, out SysTime result)
{
    if (tokens.length < 5)
        return false;
    int day, year;
    int hour, minute, second;
    if (!toInt(tokens[1], day) || !toInt(tokens[3], year) || !parseHMS(tokens[4], hour, minute, second))
        return false;
    auto month = monthIndex(tokens[2]);
    if (month == 0)
        return false;
    return makeTime(year, month, day, hour, minute, second, result);
}

private bool parseRFC850(string[] tokens, out SysTime result)
{
    if (tokens.length < 3)
        return false;
    auto pieces = findSplit(tokens[1], "-");
    if (!pieces[1].length)
        return false;
    auto rest = findSplit(pieces[2], "-");
    int day, year;
    int hour, minute, second;
    if (!toInt(pieces[0], day) || !toInt(rest[2], year) || !parseHMS(tokens[2], hour, minute, second))
        return false;
    auto month = monthIndex(rest[0]);
    if (month == 0)
        return false;
    if (year < 100)
        year += year >= 69 ? 1900 : 2000;
    return makeTime(year, month, day, hour, minute, second, result);
}

private bool parseAsctime(string[] tokens, out SysTime result)
{
    int day, year;
    int hour, minute, second;
    if (!toInt(tokens[2], day) || !toInt(tokens[4], year) || !parseHMS(tokens[3], hour, minute, second))
        return false;
    auto month = monthIndex(tokens[1]);
    if (month == 0)
        return false;
    return makeTime(year, month, day, hour, minute, second, result);
}

private bool parseHMS(string text, out int hour, out int minute, out int second)
{
    auto first = findSplit(text, ":");
    if (!first[1].length)
        return false;
    auto secondSplit = findSplit(first[2], ":");
    if (!secondSplit[1].length)
        return false;
    auto secondsText = secondSplit[2];
    auto dot = secondsText.indexOf('.');
    if (dot >= 0)
        secondsText = secondsText[0 .. dot];
    return toInt(first[0], hour) && toInt(secondSplit[0], minute) && toInt(secondsText, second);
}

private bool toInt(string text, out int value)
{
    if (text.length == 0)
        return false;
    try
        value = to!int(text);
    catch (Exception)
        return false;
    return true;
}

private bool makeTime(int year, int month, int day, int hour, int minute, int second, out SysTime result)
{
    try
        result = SysTime(DateTime(year, month, day, hour, minute, second), UTC());
    catch (Exception)
        return false;
    return true;
}

private int monthIndex(string name)
{
    switch (name.toLower)
    {
    case "jan":
        return 1;
    case "feb":
        return 2;
    case "mar":
        return 3;
    case "apr":
        return 4;
    case "may":
        return 5;
    case "jun":
        return 6;
    case "jul":
        return 7;
    case "aug":
        return 8;
    case "sep":
        return 9;
    case "oct":
        return 10;
    case "nov":
        return 11;
    case "dec":
        return 12;
    default:
        return 0;
    }
}

unittest
{
    import core.time : dur;
    import std.datetime.systime : unixTimeToStdTime;
    import std.format : format;

    auto now = SysTime(unixTimeToStdTime(1_700_000_000L), UTC());
    auto soon = now + dur!"seconds"(6);
    static immutable days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    static immutable months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    auto header = format("%s, %02d %s %04d %02d:%02d:%02d GMT",
        days[cast(int) soon.dayOfWeek], soon.day, months[soon.month - 1], soon.year,
        soon.hour, soon.minute, soon.second);
    auto waited = retryWait(["Retry-After": header], now);
    assert(waited >= 5.9 && waited <= 6.1);

    auto past = now - dur!"seconds"(300);
    auto pastHeader = format("%s, %02d %s %04d %02d:%02d:%02d GMT",
        days[cast(int) past.dayOfWeek], past.day, months[past.month - 1], past.year,
        past.hour, past.minute, past.second);
    assert(retryWait(["Retry-After": pastHeader], now) == 0);
    assert(retryWait(["Retry-After": "soon", "RateLimit-Reset": "1.5"], now) == 1.5);
    assert(retryWait(["Retry-After": "-3"], now) == 0);
    string[string] none;
    assert(retryWait(none, now) == 2);
    assert(retryWait(["retry-after": "4"], now) == 4);
    assert(retryWait(["Retry-After": "Tue, 27 Oct 2099 21:00:00"], now) == 10);
    assert(retryWait(["Retry-After": "120", "RateLimit-Reset": "5"], now) == 10);
}

version (unittest)
{
    package HTTPResult httpResult(int status, string body, string[string] headers = null)
    {
        return HTTPResult(status, reasonPhrase(status), headers, body);
    }

    class FakeTransport : Transport
    {
        HTTPResult[] queued;
        HTTPResult delegate(string url, string[string] headers) responder;
        Exception failure;
        string[] urls;
        string[string][] headerLog;

        override HTTPResult get(string url, string[string] headers, double timeoutSeconds)
        {
            assert(timeoutSeconds > 0);
            urls ~= url;
            headerLog ~= headers.dup;
            if (failure !is null)
                throw failure;
            if (responder !is null)
                return responder(url, headers);
            assert(queued.length > 0, "no queued response for " ~ url);
            auto next = queued[0];
            queued = queued[1 .. $];
            return next;
        }
    }

    class RecordingSleeper : Sleeper
    {
        double[] delays;

        override void sleepSeconds(double seconds)
        {
            delays ~= seconds;
        }
    }
}
