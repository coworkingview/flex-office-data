package io.github.coworkingview;

/** Package version. The jar manifest wins when the class is loaded from the jar. */
final class Version {
    static final String VERSION = "0.1.0";

    private Version() {}

    static String version() {
        Package pkg = Client.class.getPackage();
        String fromJar = pkg == null ? null : pkg.getImplementationVersion();
        return fromJar == null || fromJar.isEmpty() ? VERSION : fromJar;
    }

    static String userAgent() {
        return "coworkingview-java/" + version() + " (+https://github.com/coworkingview/flex-office-data)";
    }
}
