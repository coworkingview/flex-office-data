# frozen_string_literal: true

module RedmineCoworkingview
  # HTML for the two wiki macros. Every interpolated value goes through +h+.
  class Presenter
    include Escape

    def initialize(dataset)
      @dataset = dataset
    end

    def rate(city, product = nil)
      slug = city.to_s.strip
      return error("Pass a city slug, for example berlin.") if slug.empty?

      chosen = product.to_s.strip
      chosen = DEFAULT_PRODUCT if chosen.empty?
      rows = rows_for(slug)
      return error("No Price Index rates for #{slug}.") if rows.empty?

      row = rows.find { |item| item.product.to_s.casecmp?(chosen) }
      return error("No Price Index product #{chosen} for #{slug}.") if row.nil?

      single(row)
    end

    def rates(city)
      slug = city.to_s.strip
      return error("Pass a city slug, for example berlin.") if slug.empty?

      rows = rows_for(slug)
      return error("No Price Index rates for #{slug}.") if rows.empty?

      table(rows)
    end

    private

    def rows_for(slug)
      needle = slug.downcase
      @dataset.rows.select { |row| row.city_slug.to_s.downcase == needle }
    end

    def single(row)
      parts = []
      parts << %(<div class="coworkingview coworkingview-rate">)
      parts << "<p>#{span('coworkingview-city', row.city_name)} #{span('coworkingview-product', row.product)}</p>"
      parts << "<ul>"
      parts << "<li>median #{span('coworkingview-median', format_number(row.median))}</li>"
      parts << "<li>p25-p75 #{span('coworkingview-spread', spread(row))}</li>"
      parts << "<li>currency #{span('coworkingview-currency', row.currency)}</li>"
      parts << "<li>unit #{span('coworkingview-unit', row.unit)}</li>"
      parts << "<li>sample size #{span('coworkingview-sample', format_number(row.sample_size))}</li>"
      parts << "</ul>"
      parts << footer
      parts << "</div>"
      parts.join("\n")
    end

    def table(rows)
      parts = []
      parts << %(<div class="coworkingview coworkingview-rates">)
      parts << %(<table class="list coworkingview">)
      parts << "<caption>#{h(rows.first.city_name)}</caption>"
      parts << "<thead><tr>"
      parts << "<th>Product</th><th>Median</th><th>P25-P75</th><th>Currency</th><th>Unit</th><th>Sample size</th>"
      parts << "</tr></thead>"
      parts << "<tbody>"
      rows.each do |row|
        parts << "<tr>"
        parts << cell("coworkingview-product", row.product)
        parts << cell("coworkingview-median", format_number(row.median))
        parts << cell("coworkingview-spread", spread(row))
        parts << cell("coworkingview-currency", row.currency)
        parts << cell("coworkingview-unit", row.unit)
        parts << cell("coworkingview-sample", format_number(row.sample_size))
        parts << "</tr>"
      end
      parts << "</tbody></table>"
      parts << footer
      parts << "</div>"
      parts.join("\n")
    end

    def footer
      parts = []
      if @dataset.as_of
        parts << %(<p class="coworkingview-as-of">as of #{h(@dataset.as_of)}</p>)
      end
      if @dataset.source == "snapshot"
        parts << %(<p class="coworkingview-source">Bundled snapshot.</p>)
      end
      parts << attribution
      parts.join("\n")
    end

    def attribution
      href = h(ATTRIBUTION_URL)
      text = h(ATTRIBUTION_TEXT)
      %(<p class="coworkingview-attribution"><a href="#{href}">#{text}</a></p>)
    end

    def error(message)
      %(<p class="coworkingview-error">#{h(message)}</p>)
    end

    def span(css, value)
      %(<span class="#{css}">#{h(value)}</span>)
    end

    def cell(css, value)
      %(<td class="#{css}">#{h(value)}</td>)
    end

    def spread(row)
      if !row.p25.nil? && !row.p75.nil?
        "#{format_number(row.p25)}-#{format_number(row.p75)}"
      elsif !row.p25.nil?
        format_number(row.p25)
      elsif !row.p75.nil?
        format_number(row.p75)
      else
        "—"
      end
    end

    def format_number(value)
      return "" if value.nil?
      return value.to_s unless value.is_a?(Numeric)
      return value.to_s unless value.finite?
      return value.to_i.to_s if value == value.to_i

      value.to_s
    end
  end
end
