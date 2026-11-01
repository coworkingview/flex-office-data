package com.coworkingview.eclipse;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Properties;

import org.osgi.framework.Bundle;
import org.osgi.framework.FrameworkUtil;

/** The Price Index JSON shipped in this plug-in, used when the API cannot be reached. */
public final class Snapshot {

    private Snapshot() {
    }

    public static PriceIndex load() throws RatesException {
        String json = read("resources/snapshot.json");
        PriceIndex parsed = RatesParser.parse(json);
        return new PriceIndex(
                parsed.cities(),
                parsed.asOf(),
                parsed.attribution(),
                parsed.licenseUrl(),
                Origin.SNAPSHOT,
                null);
    }

    /** Calendar day the bundled file was saved, or an empty string. */
    public static String capturedOn() {
        try (InputStream input = open("resources/snapshot.properties")) {
            Properties properties = new Properties();
            properties.load(input);
            String captured = properties.getProperty("captured");
            return captured == null ? "" : captured.trim();
        } catch (IOException | RatesException exception) {
            return "";
        }
    }

    private static String read(String path) throws RatesException {
        try (InputStream input = open(path)) {
            return new String(input.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException exception) {
            throw new RatesException("SNAPSHOT", "Could not read " + path + ".");
        }
    }

    private static InputStream open(String path) throws RatesException {
        Bundle bundle = FrameworkUtil.getBundle(Snapshot.class);
        if (bundle == null) {
            throw new RatesException("SNAPSHOT", "The plug-in bundle is not available.");
        }
        java.net.URL entry = bundle.getEntry(path);
        if (entry == null) {
            throw new RatesException("SNAPSHOT", path + " is not in the plug-in.");
        }
        try {
            return entry.openStream();
        } catch (IOException exception) {
            throw new RatesException("SNAPSHOT", "Could not open " + path + ".");
        }
    }
}
