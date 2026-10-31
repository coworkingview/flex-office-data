package io.github.coworkingview;

import java.util.Objects;

/**
 * Rows, or one record, plus the attribution that has to travel with them.
 *
 * <p>For {@link Client#rates()} and {@link Client#cities()} this carries the Price Index
 * attribution, the licence URL ({@link #getLicense()}) and {@link #getAsOf()}. Publish
 * the attribution with any figure you republish: the index is CC BY 4.0.
 *
 * <p>For {@link Client#spaces(SpacesQuery)} and {@link Client#space(String)} this carries
 * {@code meta.citation.text} as the attribution, {@code meta.citation.accessed} as
 * {@link #getAsOf()}, and {@code meta.catalogueNotice} as {@link #getNotice()}.
 * {@link #getTotal()} is the catalogue {@code pagination.total} from the first page of a
 * search, and {@code null} when the API omitted it or the call was not a search.
 *
 * @param <T> the rows or the record
 */
public final class Dataset<T> {
    private final String attribution;
    private final String license;
    private final String asOf;
    private final String notice;
    private final Long total;
    private final T data;

    Dataset(String attribution, String license, String asOf, String notice, Long total, T data) {
        this.attribution = attribution;
        this.license = license;
        this.asOf = asOf;
        this.notice = notice;
        this.total = total;
        this.data = Objects.requireNonNull(data, "data");
    }

    <U> Dataset<U> withData(U newData) {
        return new Dataset<U>(attribution, license, asOf, notice, total, newData);
    }

    /**
     * Text to show next to the data. For the Price Index this is the CC BY attribution.
     * For the catalogue it is {@code meta.citation.text}.
     *
     * @return the attribution, or {@code null} when the response omitted it
     */
    public String getAttribution() {
        return attribution;
    }

    /**
     * Licence URL of the Price Index, for example
     * {@code https://creativecommons.org/licenses/by/4.0/}.
     *
     * @return the URL, or {@code null} on catalogue results and when the response omitted it
     */
    public String getLicense() {
        return license;
    }

    /**
     * When the figures were computed (Price Index, ISO 8601) or the citation's
     * {@code accessed} date (catalogue, {@code YYYY-MM-DD}).
     *
     * @return the timestamp or date, or {@code null} when the response omitted it
     */
    public String getAsOf() {
        return asOf;
    }

    /**
     * The API's catalogue notice on reuse of operator content.
     *
     * @return the notice, or {@code null} for Price Index results and when the response omitted it
     */
    public String getNotice() {
        return notice;
    }

    /**
     * How many catalogue rows matched, which can be more than the rows returned.
     *
     * @return {@code pagination.total} from the first page, or {@code null} when the API
     *     omitted it
     */
    public Long getTotal() {
        return total;
    }

    /**
     * The rows or the record.
     *
     * @return the data, never {@code null}
     */
    public T getData() {
        return data;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof Dataset)) {
            return false;
        }
        Dataset<?> that = (Dataset<?>) other;
        return Objects.equals(attribution, that.attribution)
                && Objects.equals(license, that.license)
                && Objects.equals(asOf, that.asOf)
                && Objects.equals(notice, that.notice)
                && Objects.equals(total, that.total)
                && Objects.equals(data, that.data);
    }

    @Override
    public int hashCode() {
        return Objects.hash(attribution, license, asOf, notice, total, data);
    }

    @Override
    public String toString() {
        return "Dataset(attribution=" + attribution + ", asOf=" + asOf + ", total=" + total + ", data=" + data + ")";
    }
}
