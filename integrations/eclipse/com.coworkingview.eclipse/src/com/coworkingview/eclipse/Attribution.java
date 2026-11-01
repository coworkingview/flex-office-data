package com.coworkingview.eclipse;

import java.net.URI;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Turns the API attribution string into an SWT {@code Link} body.
 * Only https URLs on CoworkingView or Creative Commons become links.
 * The line always ends with a link to https://coworkingview.com.
 */
public final class Attribution {

    public static final String HOME = "https://coworkingview.com";

    private static final Set<String> HOSTS = Set.of(
            "coworkingview.com",
            "www.coworkingview.com",
            "creativecommons.org",
            "www.creativecommons.org");

    private static final Pattern URL = Pattern.compile("https://[A-Za-z0-9._~:/?#\\[\\]@!$&'()*+,;=%-]+");

    private Attribution() {
    }

    public static String linkText(String attribution) {
        String source = attribution == null || attribution.isBlank()
                ? "Source: CoworkingView Price Index. Licensed under CC BY 4.0."
                : attribution.trim();
        String linked = linkify(escape(source));
        return linked + " <a href=\"" + HOME + "\">CoworkingView</a>";
    }

    public static boolean allowed(String href) {
        if (href == null || href.indexOf('"') >= 0 || href.indexOf('<') >= 0 || href.indexOf('>') >= 0) {
            return false;
        }
        URI uri;
        try {
            uri = URI.create(href);
        } catch (IllegalArgumentException exception) {
            return false;
        }
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getUserInfo() != null) {
            return false;
        }
        String host = uri.getHost();
        return host != null && HOSTS.contains(host.toLowerCase(Locale.ROOT));
    }

    private static String linkify(String escaped) {
        Matcher matcher = URL.matcher(escaped);
        StringBuilder builder = new StringBuilder();
        int last = 0;
        while (matcher.find()) {
            String full = matcher.group();
            String raw = trimTrail(full);
            builder.append(escaped, last, matcher.start());
            if (allowed(raw)) {
                builder.append("<a href=\"").append(raw).append("\">").append(raw).append("</a>");
            } else {
                builder.append(raw);
            }
            builder.append(full.substring(raw.length()));
            last = matcher.end();
        }
        builder.append(escaped.substring(last));
        return builder.toString();
    }

    private static String trimTrail(String url) {
        int end = url.length();
        while (end > 0 && ".,);".indexOf(url.charAt(end - 1)) >= 0) {
            end--;
        }
        return url.substring(0, end);
    }

    private static String escape(String text) {
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }
}
