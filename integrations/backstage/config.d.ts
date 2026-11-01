export interface Config {
  /**
   * CoworkingView frontend plugin.
   */
  coworkingview?: {
    /**
     * City slug requested when the page or card first loads.
     * Example: berlin
     * @visibility frontend
     */
    defaultCity?: string;

    /**
     * Origin and path prefix for GET /v1/market/rates and GET /v1/properties.
     * Defaults to https://api.coworkingview.com.
     * Set this to the Backstage proxy mount when the browser origin is not
     * allowed by that API, for example ${backend.baseUrl}/api/proxy/coworkingview.
     * @visibility frontend
     */
    baseUrl?: string;
  };
}
