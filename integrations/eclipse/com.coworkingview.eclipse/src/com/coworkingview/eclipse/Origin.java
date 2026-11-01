package com.coworkingview.eclipse;

/** Where the rows on screen came from. */
public enum Origin {
    /** HTTPS response from the public API. */
    LIVE,
    /** JSON shipped inside the plug-in. */
    SNAPSHOT
}
