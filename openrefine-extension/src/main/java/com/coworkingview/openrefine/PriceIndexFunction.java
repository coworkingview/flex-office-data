package com.coworkingview.openrefine;

import com.google.refine.expr.EvalError;
import com.google.refine.grel.Function;
import java.util.Properties;
import java.util.concurrent.atomic.AtomicReference;

/**
 * {@code coworkingviewPriceIndex(city[, product])}.
 *
 * <p>Looks up one published figure from
 * {@code GET https://api.coworkingview.com/v1/market/rates}. The default
 * product is {@code flex_desk}. The returned object carries the amounts the
 * API published and the attribution string. A missing city or product is an
 * error, not a guessed number.
 */
public final class PriceIndexFunction implements Function {
    private static final long serialVersionUID = 1L;
    private static final AtomicReference<RatesClient> CLIENT = new AtomicReference<RatesClient>(RatesClient.create());

    public PriceIndexFunction() {
    }

    /** Test hook. The registered function itself stays stateless. */
    static void use(RatesClient client) {
        CLIENT.set(client);
    }

    static void resetClient() {
        CLIENT.set(RatesClient.create());
    }

    @Override
    public Object call(Properties bindings, Object[] args) {
        if (args == null || args.length < 1 || args.length > 2) {
            return error("coworkingviewPriceIndex expects a city and an optional product, for example coworkingviewPriceIndex(\"berlin\", \"flex_desk\")");
        }
        try {
            String city = PriceIndexParser.citySlug(args[0]);
            String product = args.length == 1
                    ? PriceIndexParser.DEFAULT_PRODUCT
                    : PriceIndexParser.productCode(args[1]);
            return CLIENT.get().priceIndex(city, product);
        } catch (PriceIndexException ex) {
            return error(ex.getMessage());
        }
    }

    private static EvalError error(String message) {
        return new EvalError(message);
    }

    @Override
    public String getDescription() {
        return "Published CoworkingView Price Index figure for a city. "
                + "The optional product defaults to flex_desk (a hot desk, monthly). "
                + "Other codes include fix_desk, private_office, day_pass and meeting_room. "
                + "The object contains the median and whichever of p25, p75, min, max, currency and sampleSize the API published, plus the attribution. "
                + "Price Index data is CC BY 4.0.";
    }

    @Override
    public String getParams() {
        return "string city, [string product]";
    }

    @Override
    public String getReturns() {
        return "object";
    }
}
