package com.coworkingview.eclipse;

import java.math.BigDecimal;
import java.util.Comparator;
import java.util.Locale;

import org.eclipse.jface.action.Action;
import org.eclipse.jface.action.MenuManager;
import org.eclipse.jface.viewers.ArrayContentProvider;
import org.eclipse.jface.viewers.ColumnLabelProvider;
import org.eclipse.jface.viewers.ColumnViewerToolTipSupport;
import org.eclipse.jface.viewers.TableViewer;
import org.eclipse.jface.viewers.TableViewerColumn;
import org.eclipse.jface.viewers.Viewer;
import org.eclipse.jface.viewers.ViewerComparator;
import org.eclipse.jface.viewers.ViewerFilter;
import org.eclipse.swt.SWT;
import org.eclipse.swt.events.ControlAdapter;
import org.eclipse.swt.events.ControlEvent;
import org.eclipse.swt.events.SelectionListener;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.program.Program;
import org.eclipse.swt.widgets.Button;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.Link;
import org.eclipse.swt.widgets.Menu;
import org.eclipse.swt.widgets.Table;
import org.eclipse.swt.widgets.TableColumn;
import org.eclipse.swt.widgets.Text;

/**
 * The body of the CoworkingView Workspace Prices view. {@link PricesView} hosts this
 * composite and passes a refresh callback.
 */
public final class PricesPanel extends Composite {

    private final Text filter;
    private final TableViewer viewer;
    private final Link attribution;
    private final Label status;
    private final Label footnote;
    private final Runnable onRefresh;
    private PriceIndex index = new PriceIndex(java.util.List.of(), null, null, null, Origin.SNAPSHOT, null);
    private int sortColumn;
    private int sortDirection = SWT.UP;

    public PricesPanel(Composite parent, int style, Runnable onRefresh) {
        super(parent, style);
        this.onRefresh = onRefresh;
        GridLayout layout = new GridLayout(1, false);
        layout.marginWidth = 8;
        layout.marginHeight = 8;
        setLayout(layout);

        Label intro = new Label(this, SWT.WRAP);
        intro.setText("Monthly hot desk, dedicated desk, and private office ranges from the CoworkingView Price Index.");
        intro.setLayoutData(wrapData());

        Composite bar = new Composite(this, SWT.NONE);
        bar.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false));
        GridLayout barLayout = new GridLayout(3, false);
        barLayout.marginWidth = 0;
        barLayout.marginHeight = 0;
        bar.setLayout(barLayout);

        Label filterLabel = new Label(bar, SWT.NONE);
        filterLabel.setText("Filter cities:");
        filter = new Text(bar, SWT.BORDER | SWT.SEARCH | SWT.ICON_CANCEL);
        filter.setMessage("City, slug, or country");
        filter.setLayoutData(new GridData(SWT.FILL, SWT.CENTER, true, false));
        Button refresh = new Button(bar, SWT.PUSH);
        refresh.setText("Refresh");
        refresh.setToolTipText("Fetch the Price Index from api.coworkingview.com");
        refresh.addSelectionListener(SelectionListener.widgetSelectedAdapter(event -> refresh()));

        viewer = new TableViewer(this, SWT.FULL_SELECTION | SWT.BORDER | SWT.H_SCROLL | SWT.V_SCROLL);
        Table table = viewer.getTable();
        table.setHeaderVisible(true);
        table.setLinesVisible(true);
        table.setLayoutData(new GridData(SWT.FILL, SWT.FILL, true, true));
        ColumnViewerToolTipSupport.enableFor(viewer);
        viewer.setContentProvider(ArrayContentProvider.getInstance());

        addTextColumn("City", 170, city -> city.name(), city -> city.slug());
        addTextColumn("Country", 80, city -> city.countryCode() == null ? "" : city.countryCode(), null);
        addDeskColumn("Hot desk", 130, CityPrice::hotDesk);
        addDeskColumn("Dedicated desk", 140, CityPrice::dedicatedDesk);
        addDeskColumn("Private office", 140, CityPrice::privateOffice);
        addTextColumn("Currency", 80, city -> city.currency() == null ? "" : city.currency(), null);
        hookSort(table.getColumn(0), 0, Comparator.comparing(CityPrice::name, String.CASE_INSENSITIVE_ORDER));
        hookSort(table.getColumn(1), 1, Comparator.comparing(
                city -> city.countryCode() == null ? "" : city.countryCode(), String.CASE_INSENSITIVE_ORDER));
        hookSort(table.getColumn(2), 2, medianComparator(CityPrice::hotDesk));
        hookSort(table.getColumn(3), 3, medianComparator(CityPrice::dedicatedDesk));
        hookSort(table.getColumn(4), 4, medianComparator(CityPrice::privateOffice));
        hookSort(table.getColumn(5), 5, Comparator.comparing(
                city -> city.currency() == null ? "" : city.currency(), String.CASE_INSENSITIVE_ORDER));
        table.setSortColumn(table.getColumn(0));
        table.setSortDirection(SWT.UP);
        viewer.setComparator(comparator(Comparator.comparing(CityPrice::name, String.CASE_INSENSITIVE_ORDER)));

        viewer.addFilter(new ViewerFilter() {
            @Override
            public boolean select(Viewer viewer, Object parentElement, Object element) {
                String query = filter.getText().trim().toLowerCase(Locale.ROOT);
                if (query.isEmpty()) {
                    return true;
                }
                CityPrice city = (CityPrice) element;
                return contains(city.name(), query) || contains(city.slug(), query) || contains(city.countryCode(), query);
            }
        });
        MenuManager menuManager = new MenuManager();
        menuManager.add(new Action("Open on coworkingview.com") {
            @Override
            public void run() {
                openCity();
            }
        });
        Menu menu = menuManager.createContextMenu(table);
        table.setMenu(menu);
        table.addDisposeListener(event -> menuManager.dispose());
        viewer.addDoubleClickListener(event -> openCity());

        footnote = new Label(this, SWT.WRAP);
        footnote.setText("A range is the published 25th–75th percentile per month. One number means those ends match, or only a median was published. * means fewer than 10 prices. Double-click a row to open that city on coworkingview.com.");
        footnote.setLayoutData(wrapData());

        attribution = new Link(this, SWT.WRAP);
        attribution.setLayoutData(wrapData());
        attribution.addSelectionListener(SelectionListener.widgetSelectedAdapter(event -> open(event.text)));

        status = new Label(this, SWT.WRAP);
        status.setLayoutData(wrapData());
        status.setText("Loading prices\u2026");
        filter.addModifyListener(event -> {
            viewer.refresh();
            status.setText(statusLine(index));
        });

        addControlListener(new ControlAdapter() {
            @Override
            public void controlResized(ControlEvent event) {
                int width = Math.max(200, getClientArea().width - 16);
                ((GridData) intro.getLayoutData()).widthHint = width;
                ((GridData) footnote.getLayoutData()).widthHint = width;
                ((GridData) attribution.getLayoutData()).widthHint = width;
                ((GridData) status.getLayoutData()).widthHint = width;
                layout(true);
            }
        });
    }

    public void show(PriceIndex next) {
        index = next;
        viewer.setInput(next.cities());
        attribution.setText(Attribution.linkText(next.attribution()));
        status.setText(statusLine(next));
        layout(true, true);
    }

    public void setStatus(String text) {
        status.setText(text);
    }

    public void setFilterText(String text) {
        filter.setText(text);
    }

    public int visibleRowCount() {
        return viewer.getTable().getItemCount();
    }

    public void focusFilter() {
        filter.setFocus();
    }

    private void refresh() {
        if (onRefresh != null) {
            onRefresh.run();
        }
    }

    private String statusLine(PriceIndex shown) {
        int total = shown.cities().size();
        int visible = viewer.getTable().getItemCount();
        String count = visible == total
                ? total + (total == 1 ? " city. " : " cities. ")
                : visible + " of " + total + " cities. ";
        String asOf = shown.asOf() == null || shown.asOf().isBlank() ? "" : " Index as of " + shown.asOf() + ".";
        if (shown.origin() == Origin.LIVE) {
            return count + "Live figures from api.coworkingview.com." + asOf;
        }
        String captured = Snapshot.capturedOn();
        String when = captured.isEmpty() ? "" : " (captured " + captured + ")";
        String why = shown.notice() == null || shown.notice().isBlank()
                ? ""
                : " The request failed: " + oneLine(shown.notice());
        return count + "Offline snapshot bundled with this plug-in" + when + "." + why + asOf;
    }

    private static String oneLine(String notice) {
        String line = notice.replace('\n', ' ').trim();
        if (line.length() > 220) {
            return line.substring(0, 220);
        }
        return line;
    }

    private void openCity() {
        Object selected = viewer.getStructuredSelection().getFirstElement();
        if (selected instanceof CityPrice city && city.slug() != null
                && city.slug().matches("[a-z0-9]+(?:-[a-z0-9]+)*")) {
            open("https://coworkingview.com/en/coworking/" + city.slug());
        }
    }

    private static void open(String href) {
        if (Attribution.allowed(href)) {
            Program.launch(href);
        }
    }

    private void addTextColumn(String title, int width, java.util.function.Function<CityPrice, String> text,
            java.util.function.Function<CityPrice, String> tip) {
        TableViewerColumn column = new TableViewerColumn(viewer, SWT.LEFT);
        column.getColumn().setText(title);
        column.getColumn().setWidth(width);
        column.setLabelProvider(new ColumnLabelProvider() {
            @Override
            public String getText(Object element) {
                return text.apply((CityPrice) element);
            }

            @Override
            public String getToolTipText(Object element) {
                return tip == null ? null : tip.apply((CityPrice) element);
            }
        });
    }

    private void addDeskColumn(String title, int width, java.util.function.Function<CityPrice, DeskQuote> quote) {
        TableViewerColumn column = new TableViewerColumn(viewer, SWT.RIGHT);
        column.getColumn().setText(title);
        column.getColumn().setWidth(width);
        column.setLabelProvider(new ColumnLabelProvider() {
            @Override
            public String getText(Object element) {
                CityPrice city = (CityPrice) element;
                return PriceText.range(quote.apply(city), Locale.getDefault());
            }

            @Override
            public String getToolTipText(Object element) {
                CityPrice city = (CityPrice) element;
                return PriceText.tooltip(quote.apply(city), city.currency(), Locale.getDefault());
            }
        });
    }

    private void hookSort(TableColumn column, int index, Comparator<CityPrice> ordering) {
        column.addSelectionListener(SelectionListener.widgetSelectedAdapter(event -> {
            if (sortColumn == index) {
                sortDirection = sortDirection == SWT.UP ? SWT.DOWN : SWT.UP;
            } else {
                sortColumn = index;
                sortDirection = SWT.UP;
            }
            viewer.getTable().setSortColumn(column);
            viewer.getTable().setSortDirection(sortDirection);
            viewer.setComparator(comparator(ordering));
        }));
    }

    private ViewerComparator comparator(Comparator<CityPrice> ordering) {
        return new ViewerComparator() {
            @Override
            public int compare(Viewer viewer, Object left, Object right) {
                int result = ordering.compare((CityPrice) left, (CityPrice) right);
                return sortDirection == SWT.DOWN ? -result : result;
            }
        };
    }

    private static Comparator<CityPrice> medianComparator(java.util.function.Function<CityPrice, DeskQuote> quote) {
        return Comparator.comparing(city -> median(quote.apply(city)), Comparator.nullsLast(Comparator.naturalOrder()));
    }

    private static BigDecimal median(DeskQuote quote) {
        if (quote == null || quote.medianText() == null) {
            return null;
        }
        try {
            return new BigDecimal(quote.medianText());
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static boolean contains(String value, String query) {
        return value != null && value.toLowerCase(Locale.ROOT).contains(query);
    }

    private static GridData wrapData() {
        GridData data = new GridData(SWT.FILL, SWT.CENTER, true, false);
        data.widthHint = 640;
        return data;
    }
}
