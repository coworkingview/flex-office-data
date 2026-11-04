"""GTK4 / libadwaita window for CoworkingView Rates."""

from __future__ import annotations

import os
import sys
import threading
import urllib.parse
from datetime import datetime, timezone

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gio, GLib, Gtk

from coworkingview_rates import __version__
from coworkingview_rates.index import (
    City,
    Figure,
    PriceIndex,
    RatesError,
    cache_file,
    fetch_market,
    format_amount,
    load_cache,
    parse_index,
    save_cache,
)

PRICE_INDEX_URL = "https://coworkingview.com/en/tools/price-index"
HOMEPAGE = "https://coworkingview.com"
ISSUE_URL = "https://github.com/coworkingview/flex-office-data/issues"

PRODUCT_LABELS = {
    "flex_desk": "Flex desk",
    "fix_desk": "Fixed desk",
    "private_office": "Private office",
    "exclusive_bereich": "Exclusive area",
    "day_pass": "Day pass",
    "meeting_room": "Meeting room",
    "event_space": "Event space",
    "virtual_office": "Virtual office",
    "membership": "Membership",
}
UNIT_LABELS = {"month": "per month", "day": "per day", "hour": "per hour"}


def product_label(product: str) -> str:
    if product in PRODUCT_LABELS:
        return PRODUCT_LABELS[product]
    return product.replace("_", " ").capitalize()


def office_url(slug: str) -> str:
    return "https://coworkingview.com/en/office-space/" + urllib.parse.quote(slug)


def save_window_png(window: Gtk.Window, path: str) -> None:
    """Write the window contents, including the header bar, to a PNG file."""
    width = window.get_width()
    height = window.get_height()
    if width < 100 or height < 100:
        raise RuntimeError(f"window is {width}x{height}")
    paintable = Gtk.WidgetPaintable.new(window)
    snapshot = Gtk.Snapshot()
    paintable.snapshot(snapshot, width, height)
    node = snapshot.to_node()
    if node is None:
        raise RuntimeError("window snapshot is empty")
    native = window.get_native()
    renderer = None if native is None else native.get_renderer()
    if renderer is None:
        raise RuntimeError("window has no renderer")
    texture = renderer.render_texture(node, None)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    if not texture.save_to_png(path):
        raise RuntimeError(f"could not write {path}")


class RatesWindow(Adw.ApplicationWindow):
    """City list and the Price Index figures for the selected city."""

    def __init__(self, app: Adw.Application) -> None:
        super().__init__(application=app, title="CoworkingView Rates")
        self.set_default_size(1000, 700)
        self._index: PriceIndex | None = None
        self._cities: dict[str, City] = {}
        self._selected: str | None = None
        self._query = ""
        self._generation = 0
        self._rebuilding = False
        self._capture_tries = 0
        self._scrolled_for_shot = False
        self._shot = os.environ.get("COWORKINGVIEW_RATES_SCREENSHOT") or ""
        self._smoke = os.environ.get("COWORKINGVIEW_RATES_SMOKE") or ""

        self._install_css()
        self._build_ui()
        reload_action = Gio.SimpleAction.new("reload", None)
        reload_action.connect("activate", lambda *_args: self.reload())
        self.add_action(reload_action)
        search_action = Gio.SimpleAction.new("search", None)
        search_action.connect("activate", lambda *_args: self.search.grab_focus())
        self.add_action(search_action)

    def _install_css(self) -> None:
        provider = Gtk.CssProvider()
        provider.load_from_data(
            b"""
            .price-card { padding: 12px 16px; }
            .attribution-bar { padding: 8px 16px 12px; }
            """
        )
        display = Gdk.Display.get_default()
        if display is not None:
            Gtk.StyleContext.add_provider_for_display(
                display,
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )

    def _build_ui(self) -> None:
        sidebar_header = Adw.HeaderBar()
        sidebar_header.set_title_widget(Adw.WindowTitle.new("Cities", ""))
        self.search = Gtk.SearchEntry(placeholder_text="Search cities", hexpand=True)
        self.search.set_margin_start(12)
        self.search.set_margin_end(12)
        self.search.set_margin_top(6)
        self.search.set_margin_bottom(6)
        self.search.connect("changed", self._on_search)
        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self._on_search_key)
        self.search.add_controller(key)

        self.listbox = Gtk.ListBox()
        self.listbox.add_css_class("navigation-sidebar")
        self.listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.listbox.set_filter_func(self._filter_row)
        self.listbox.connect("row-selected", self._on_row_selected)
        self.sidebar_scroll = Gtk.ScrolledWindow(vexpand=True)
        self.sidebar_scroll.set_child(self.listbox)
        self.empty_filter = Gtk.Label(label="No matching city")
        self.empty_filter.add_css_class("dim-label")
        self.empty_filter.set_margin_top(18)
        self.empty_filter.set_margin_bottom(18)
        self.empty_filter.set_visible(False)

        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.append(self.search)
        side.append(self.sidebar_scroll)
        side.append(self.empty_filter)
        side_toolbar = Adw.ToolbarView()
        side_toolbar.add_top_bar(sidebar_header)
        side_toolbar.set_content(side)

        header = Adw.HeaderBar()
        self.window_title = Adw.WindowTitle.new("CoworkingView Rates", "")
        header.set_title_widget(self.window_title)
        self.refresh_btn = Gtk.Button.new_from_icon_name("view-refresh-symbolic")
        self.refresh_btn.set_tooltip_text("Download prices again")
        self.refresh_btn.connect("clicked", lambda *_args: self.reload())
        menu = Gio.Menu()
        menu.append("Price Index on the web", "app.price-index")
        menu.append("About CoworkingView Rates", "app.about")
        menu_btn = Gtk.MenuButton(icon_name="open-menu-symbolic", menu_model=menu, tooltip_text="Menu")
        header.pack_end(menu_btn)
        header.pack_end(self.refresh_btn)

        self.banner = Adw.Banner(button_label="Try again")
        self.banner.set_revealed(False)
        self.banner.connect("button-clicked", lambda *_args: self.reload())

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.add_named(self._loading_page(), "loading")
        self.stack.add_named(self._offline_page(), "offline")
        self.stack.add_named(self._simple_status("empty", "No cities", "system-search-symbolic", "This download did not include any cities."), "empty")
        self.stack.add_named(self._simple_status("nomatch", "No matching city", "system-search-symbolic", "Try a different name, slug or country code."), "nomatch")
        self.unpublished_page = Adw.StatusPage(icon_name="dialog-information-symbolic", title="No published index")
        self.stack.add_named(self.unpublished_page, "unpublished")
        self.stack.add_named(self._prices_page(), "prices")
        self.stack.set_visible_child_name("loading")

        content_toolbar = Adw.ToolbarView()
        content_toolbar.add_top_bar(header)
        content_toolbar.add_top_bar(self.banner)
        content_toolbar.set_content(self.stack)

        split = Adw.NavigationSplitView()
        split.set_min_sidebar_width(260)
        split.set_max_sidebar_width(320)
        split.set_sidebar(Adw.NavigationPage.new(side_toolbar, "Cities"))
        split.set_content(Adw.NavigationPage.new(content_toolbar, "Prices"))
        self.set_content(split)

    def _loading_page(self) -> Adw.StatusPage:
        page = Adw.StatusPage(
            title="Loading prices",
            description="Fetching the CoworkingView Price Index.",
        )
        spinner = Gtk.Spinner(spinning=True)
        spinner.set_size_request(32, 32)
        page.set_child(spinner)
        return page

    def _offline_page(self) -> Adw.StatusPage:
        self.offline_page = Adw.StatusPage(icon_name="network-offline-symbolic", title="Prices are unavailable")
        retry = Gtk.Button(label="Try again")
        retry.add_css_class("pill")
        retry.add_css_class("suggested-action")
        retry.connect("clicked", lambda *_args: self.reload())
        self.offline_page.set_child(retry)
        return self.offline_page

    def _simple_status(self, _name: str, title: str, icon: str, description: str) -> Adw.StatusPage:
        return Adw.StatusPage(icon_name=icon, title=title, description=description)

    def _prices_page(self) -> Gtk.Widget:
        self.link_box = Gtk.Box(spacing=12)
        self.link_box.set_margin_start(16)
        self.link_box.set_margin_end(16)
        self.link_box.set_margin_top(12)
        self.card_box = Gtk.Grid()
        self.card_box.set_column_spacing(12)
        self.card_box.set_row_spacing(12)
        self.card_box.set_column_homogeneous(True)
        self.card_box.set_margin_start(16)
        self.card_box.set_margin_end(16)
        self.card_box.set_margin_top(12)
        self.card_box.set_margin_bottom(16)
        clamp = Adw.Clamp()
        clamp.set_maximum_size(760)
        clamp.set_tightening_threshold(560)
        clamp.set_child(self.card_box)
        scroll = Gtk.ScrolledWindow(vexpand=True)
        scroll.set_child(clamp)
        self.attribution = Gtk.Label(xalign=0, wrap=True, selectable=True)
        self.attribution.add_css_class("caption")
        self.attribution.add_css_class("dim-label")
        self.attribution.add_css_class("attribution-bar")
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        page.append(self.link_box)
        page.append(scroll)
        page.append(Gtk.Separator())
        page.append(self.attribution)
        return page

    def prepare(self) -> None:
        """Load synchronously when a screenshot or an offline smoke check is running."""
        if self._shot or self._smoke:
            self.load_blocking()

    def start(self) -> None:
        if self._shot:
            GLib.timeout_add(400, self._capture_soon)
            return
        if self._smoke:
            GLib.timeout_add(200, self._report_smoke)
            return
        self.reload()

    def load_blocking(self) -> None:
        try:
            data = fetch_market()
            index = parse_index(data)
            saved_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            save_cache(data, cache_file(), saved_at)
            self.show_index(index, problem=None, saved_at=saved_at)
        except RatesError as err:
            self._show_failure(str(err))
        except Exception as err:
            self._show_failure(f"Could not load prices. {err}")

    def reload(self) -> None:
        self._generation += 1
        generation = self._generation
        self.refresh_btn.set_sensitive(False)
        if self._index is None:
            self.stack.set_visible_child_name("loading")
            self.banner.set_revealed(False)

        def work() -> None:
            try:
                data = fetch_market()
                index = parse_index(data)
                saved_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                save_cache(data, cache_file(), saved_at)
                GLib.idle_add(self._deliver, generation, index, None, saved_at)
            except RatesError as err:
                GLib.idle_add(self._deliver_error, generation, str(err))
            except Exception as err:
                GLib.idle_add(self._deliver_error, generation, f"Could not load prices. {err}")

        threading.Thread(target=work, daemon=True).start()

    def _deliver(self, generation: int, index: PriceIndex, problem: str | None, saved_at: str) -> bool:
        if generation != self._generation:
            return False
        self.refresh_btn.set_sensitive(True)
        self.show_index(index, problem=problem, saved_at=saved_at)
        return False

    def _deliver_error(self, generation: int, message: str) -> bool:
        if generation != self._generation:
            return False
        self.refresh_btn.set_sensitive(True)
        self._show_failure(message)
        return False

    def _show_failure(self, message: str) -> None:
        cached = load_cache(cache_file())
        if cached is not None:
            index, saved_at = cached
            self.show_index(index, problem=message, saved_at=saved_at)
            return
        self._index = None
        self.offline_page.set_description(
            message + "\n\nSaved prices will appear here after one successful download."
        )
        self.window_title.set_title("CoworkingView Rates")
        self.window_title.set_subtitle("")
        self.banner.set_revealed(False)
        self.stack.set_visible_child_name("offline")

    def show_index(self, index: PriceIndex, problem: str | None, saved_at: str | None) -> None:
        self._index = index
        position = self.sidebar_scroll.get_vadjustment().get_value()
        self._rebuild_rows(index)
        if problem:
            when = (saved_at or "")[:10]
            text = "Showing saved prices"
            if when:
                text += f" from {when}"
            text += ". A new download failed."
            self.banner.set_title(text)
            self.banner.set_revealed(True)
        else:
            self.banner.set_revealed(False)
        if index.attribution:
            self.attribution.set_label(index.attribution)
        else:
            self.attribution.set_label(
                "Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index). "
                "Licensed under CC BY 4.0."
            )
        if not index.cities:
            self.window_title.set_title("CoworkingView Rates")
            self.window_title.set_subtitle("No cities in this download")
            self.stack.set_visible_child_name("empty")
            return
        self._select_slug(self._preferred_slug(index))
        if not self._shot:
            GLib.idle_add(self._restore_scroll, position)

    def _restore_scroll(self, position: float) -> bool:
        adjustment = self.sidebar_scroll.get_vadjustment()
        adjustment.set_value(min(position, adjustment.get_upper()))
        return False

    def _preferred_slug(self, index: PriceIndex) -> str | None:
        slugs = {city.slug for city in index.cities}
        if self._shot and "berlin" in slugs:
            return "berlin"
        if self._selected in slugs:
            return self._selected
        return index.cities[0].slug

    def _rebuild_rows(self, index: PriceIndex) -> None:
        self._rebuilding = True
        try:
            while (row := self.listbox.get_row_at_index(0)) is not None:
                self.listbox.remove(row)
            self._cities = {city.slug: city for city in index.cities}
            for city in index.cities:
                self.listbox.append(self._row(city))
        finally:
            self._rebuilding = False
        self._update_filter_empty()

    def _row(self, city: City) -> Gtk.ListBoxRow:
        name = Gtk.Label(label=city.name, xalign=0)
        subtitle = Gtk.Label(label=self._subtitle(city), xalign=0)
        subtitle.add_css_class("dim-label")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.append(name)
        box.append(subtitle)
        row = Gtk.ListBoxRow()
        row.set_child(box)
        row.slug = city.slug  # type: ignore[attr-defined]
        return row

    def _subtitle(self, city: City) -> str:
        if not city.published:
            return "Not enough prices yet"
        parts: list[str] = []
        if city.country_code:
            parts.append(city.country_code)
        if city.entry_median is not None:
            parts.append("from " + format_amount(city.entry_median, city.currency))
        elif city.currency:
            parts.append(city.currency)
        return " · ".join(parts) if parts else city.slug

    def _filter_row(self, row: Gtk.ListBoxRow) -> bool:
        if not self._query:
            return True
        city = self._cities.get(getattr(row, "slug", ""))
        if city is None:
            return False
        blob = f"{city.name} {city.slug} {city.country_code or ''}".casefold()
        return self._query in blob

    def _shown(self, row: Gtk.ListBoxRow) -> bool:
        # ListBox filtering clears child-visible and leaves the visible flag set.
        return bool(row.get_visible() and row.get_child_visible())

    def _on_search(self, entry: Gtk.SearchEntry) -> None:
        self._query = entry.get_text().strip().casefold()
        self.listbox.invalidate_filter()
        self._update_filter_empty()
        selected = self.listbox.get_selected_row()
        if selected is None or not self._shown(selected):
            self._select_slug(None)

    def _on_search_key(self, _controller: Gtk.EventControllerKey, keyval: int, _code: int, _state: Gdk.ModifierType) -> bool:
        if keyval == Gdk.KEY_Escape and self.search.get_text():
            self.search.set_text("")
            return True
        return False

    def _update_filter_empty(self) -> None:
        visible = False
        index = 0
        while (row := self.listbox.get_row_at_index(index)) is not None:
            index += 1
            if self._shown(row):
                visible = True
                break
        has_rows = index > 0
        self.empty_filter.set_visible(has_rows and not visible)
        self.sidebar_scroll.set_visible(not has_rows or visible)

    def _select_slug(self, slug: str | None) -> None:
        chosen = None
        fallback = None
        index = 0
        while (row := self.listbox.get_row_at_index(index)) is not None:
            index += 1
            if not self._shown(row):
                continue
            if fallback is None:
                fallback = row
            if slug and getattr(row, "slug", None) == slug:
                chosen = row
                break
        target = chosen or fallback
        if target is None:
            self.stack.set_visible_child_name("nomatch" if self._query else "empty")
            return
        self.listbox.select_row(target)

    def _on_row_selected(self, _box: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        if self._rebuilding or row is None:
            return
        city = self._cities.get(getattr(row, "slug", ""))
        if city is None:
            return
        self._selected = city.slug
        self._show_city(city)

    def _show_city(self, city: City) -> None:
        self.window_title.set_title(city.name)
        bits: list[str] = []
        if city.country_code:
            bits.append(city.country_code)
        if city.currency:
            bits.append(city.currency)
        if self._index and self._index.as_of:
            bits.append(self._index.as_of[:10])
        self.window_title.set_subtitle(" · ".join(bits))
        if not city.published:
            self.unpublished_page.set_title(city.name)
            self.unpublished_page.set_description(
                f"{city.name} is listed, and there are not enough prices to publish an index yet."
            )
            self.stack.set_visible_child_name("unpublished")
            return
        if not city.figures and city.entry_median is None:
            self.unpublished_page.set_title(city.name)
            self.unpublished_page.set_description(f"{city.name} has no product figures in this download.")
            self.stack.set_visible_child_name("unpublished")
            return
        self._fill_links(city)
        self._fill_cards(city)
        self.stack.set_visible_child_name("prices")

    def _clear(self, box: Gtk.Widget) -> None:
        child = box.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            box.remove(child)
            child = nxt

    def _fill_links(self, city: City) -> None:
        self._clear(self.link_box)
        offices = Gtk.LinkButton(uri=office_url(city.slug), label=f"Offices in {city.name}")
        index = Gtk.LinkButton(uri=PRICE_INDEX_URL, label="Price Index")
        for link in (offices, index):
            link.set_halign(Gtk.Align.START)
            self.link_box.append(link)

    def _fill_cards(self, city: City) -> None:
        self._clear(self.card_box)
        widgets: list[Gtk.Widget] = []
        if city.entry_median is not None:
            widgets.append(self._entry_card(city))
        widgets.extend(self._figure_card(city, figure) for figure in city.figures)
        for index, widget in enumerate(widgets):
            self.card_box.attach(widget, index % 2, index // 2, 1, 1)

    def _card(self) -> Gtk.Box:
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        card.add_css_class("card")
        card.add_css_class("price-card")
        card.set_hexpand(True)
        return card

    def _entry_card(self, city: City) -> Gtk.Widget:
        card = self._card()
        title = Gtk.Label(label="Entry price", xalign=0)
        title.add_css_class("heading")
        amount = Gtk.Label(label=format_amount(city.entry_median, city.currency), xalign=0)
        amount.add_css_class("title-1")
        note = Gtk.Label(label="Median lowest monthly price per space", xalign=0)
        note.add_css_class("dim-label")
        note.set_wrap(True)
        note.set_max_width_chars(40)
        card.append(title)
        card.append(amount)
        card.append(note)
        counts = self._counts(city.property_count, city.operator_count)
        if counts:
            meta = Gtk.Label(label=counts, xalign=0)
            meta.add_css_class("dim-label")
            card.append(meta)
        return card

    def _figure_card(self, city: City, figure: Figure) -> Gtk.Widget:
        card = self._card()
        heading = Gtk.Box(spacing=8)
        title = Gtk.Label(label=product_label(figure.product), xalign=0)
        title.add_css_class("heading")
        title.set_hexpand(True)
        heading.append(title)
        unit = UNIT_LABELS.get(figure.unit or "", figure.unit or "")
        if unit:
            unit_label = Gtk.Label(label=unit, xalign=1)
            unit_label.add_css_class("dim-label")
            heading.append(unit_label)
        amount = Gtk.Label(label=format_amount(figure.median, city.currency), xalign=0)
        amount.add_css_class("title-1")
        card.append(heading)
        card.append(amount)
        if figure.p25 is not None or figure.p75 is not None:
            spread = Gtk.Label(
                label=f"{format_amount(figure.p25, city.currency)} – {format_amount(figure.p75, city.currency)}",
                xalign=0,
            )
            card.append(spread)
        meta = Gtk.Label(label=self._figure_meta(figure), xalign=0)
        meta.add_css_class("dim-label")
        meta.set_wrap(True)
        meta.set_max_width_chars(28)
        card.append(meta)
        if figure.low_confidence:
            flag = Gtk.Label(label="Fewer than 10 prices", xalign=0)
            flag.add_css_class("warning")
            card.append(flag)
        return card

    def _figure_meta(self, figure: Figure) -> str:
        parts = [f"{figure.sample_size} prices"]
        if figure.property_count is not None:
            parts.append(f"{figure.property_count} spaces")
        if figure.operator_count is not None:
            parts.append(f"{figure.operator_count} operators")
        return " · ".join(parts)

    def _counts(self, properties: int | None, operators: int | None) -> str:
        parts: list[str] = []
        if properties is not None:
            parts.append(f"{properties} spaces")
        if operators is not None:
            parts.append(f"{operators} operators")
        return " · ".join(parts)

    def _scroll_selected_near_top(self) -> None:
        row = self.listbox.get_selected_row()
        if row is None:
            return
        allocation = row.get_allocation()
        adjustment = self.sidebar_scroll.get_vadjustment()
        adjustment.set_value(max(0.0, allocation.y - allocation.height))

    def _capture_soon(self) -> bool:
        GLib.timeout_add(200, self._capture_once)
        return False

    def _capture_once(self) -> bool:
        if self.get_width() < 200 or self.get_height() < 200:
            self._capture_tries += 1
            if self._capture_tries > 25:
                print("screenshot failed: window has no size", flush=True)
                os._exit(1)
            return True
        if not self._scrolled_for_shot:
            self._scroll_selected_near_top()
            self.listbox.grab_focus()
            self._scrolled_for_shot = True
            return True
        try:
            save_window_png(self, self._shot)
        except Exception as err:
            print(f"screenshot failed: {err}", flush=True)
            os._exit(1)
        print(f"screenshot={self._shot} {self.get_width()}x{self.get_height()}", flush=True)
        app = self.get_application()
        if app is not None:
            app.quit()
        return False

    def _report_smoke(self) -> bool:
        name = self.stack.get_visible_child_name()
        title = self.offline_page.get_title() or ""
        if self._smoke == "offline" and name == "offline" and title == "Prices are unavailable":
            print(f"offline-state: {title}", flush=True)
            self._quit_ok()
            return False
        if self._smoke == "cached" and name == "prices" and self.banner.get_revealed():
            print("cached-state: ok", flush=True)
            self._quit_ok()
            return False
        if self._smoke == "search":
            self.search.set_text("zzz-no-such-city")
            GLib.timeout_add(400, self._search_smoke_empty)
            return False
        print(f"smoke failed: mode={self._smoke} page={name} title={title}", flush=True)
        os._exit(1)

    def _search_smoke_empty(self) -> bool:
        if not self.empty_filter.get_visible() or self.stack.get_visible_child_name() != "nomatch":
            print(
                f"search-state failed: empty={self.empty_filter.get_visible()} page={self.stack.get_visible_child_name()}",
                flush=True,
            )
            os._exit(1)
        self.search.set_text("berlin")
        GLib.timeout_add(400, self._search_smoke_hit)
        return False

    def _search_smoke_hit(self) -> bool:
        shown = self.window_title.get_title() or ""
        if "berlin" not in shown.casefold() or self.stack.get_visible_child_name() != "prices":
            print(f"search-state failed: title={shown} page={self.stack.get_visible_child_name()}", flush=True)
            os._exit(1)
        app = self.get_application()
        if app is not None:
            app.activate_action("about", None)
        print("search-state: ok", flush=True)
        self._quit_ok()
        return False

    def _quit_ok(self) -> None:
        app = self.get_application()
        if app is not None:
            app.quit()


class RatesApplication(Adw.Application):
    def __init__(self) -> None:
        super().__init__(application_id="com.coworkingview.Rates")
        self.win: RatesWindow | None = None

    def do_startup(self) -> None:
        Adw.Application.do_startup(self)
        about = Gio.SimpleAction.new("about", None)
        about.connect("activate", self._about)
        self.add_action(about)
        website = Gio.SimpleAction.new("price-index", None)
        website.connect(
            "activate",
            lambda *_args: Gtk.UriLauncher.new(PRICE_INDEX_URL).launch(self.win, None, None, None),
        )
        self.add_action(website)
        self.set_accels_for_action("win.reload", ["F5", "<primary>r"])
        self.set_accels_for_action("win.search", ["<primary>f"])

    def do_activate(self) -> None:
        if self.win is None:
            self.win = RatesWindow(self)
            self.win.prepare()
        self.win.present()
        self.win.start()

    def _about(self, *_args: object) -> None:
        dialog = Adw.AboutDialog(
            application_name="CoworkingView Rates",
            application_icon="com.coworkingview.Rates",
            developer_name="CoworkingView",
            version=__version__,
            website=HOMEPAGE,
            issue_url=ISSUE_URL,
            copyright="© 2026 CoworkingView",
            license_type=Gtk.License.MIT_X11,
            comments="Flexible office prices by city from the CoworkingView Price Index.",
        )
        dialog.present(self.win)


def main() -> int:
    app = RatesApplication()
    return app.run(sys.argv)
