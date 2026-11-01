package com.coworkingview.eclipse;

import org.eclipse.core.runtime.IProgressMonitor;
import org.eclipse.core.runtime.IStatus;
import org.eclipse.core.runtime.Platform;
import org.eclipse.core.runtime.Status;
import org.eclipse.core.runtime.jobs.Job;
import org.eclipse.jface.action.Action;
import org.eclipse.ui.IActionBars;
import org.eclipse.swt.SWT;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Display;
import org.eclipse.ui.ISharedImages;
import org.eclipse.ui.PlatformUI;
import org.eclipse.ui.part.ViewPart;

/**
 * Window, Show View, Other, CoworkingView, CoworkingView Workspace Prices.
 * Opening the view does not contact the network until this control is created.
 */
public final class PricesView extends ViewPart {

    public static final String ID = "com.coworkingview.eclipse.views.prices";

    private PricesPanel panel;
    private Job job;
    private int generation;

    @Override
    public void createPartControl(Composite parent) {
        panel = new PricesPanel(parent, SWT.NONE, this::reload);
        Action refresh = new Action("Refresh") {
            @Override
            public void run() {
                reload();
            }
        };
        refresh.setToolTipText("Fetch prices from api.coworkingview.com");
        refresh.setImageDescriptor(PlatformUI.getWorkbench().getSharedImages()
                .getImageDescriptor(ISharedImages.IMG_ELCL_SYNCED));
        IActionBars bars = getViewSite().getActionBars();
        bars.getToolBarManager().add(refresh);
        bars.getMenuManager().add(refresh);
        bars.updateActionBars();
        reload();
    }

    @Override
    public void setFocus() {
        if (panel != null && !panel.isDisposed()) {
            panel.focusFilter();
        }
    }

    @Override
    public void dispose() {
        generation++;
        if (job != null) {
            job.cancel();
        }
        super.dispose();
    }

    private void reload() {
        final int token = ++generation;
        if (job != null) {
            job.cancel();
        }
        if (panel != null && !panel.isDisposed()) {
            panel.setStatus("Loading prices\u2026");
        }
        job = new Job("Fetch CoworkingView prices") {
            @Override
            protected IStatus run(IProgressMonitor monitor) {
                if (monitor.isCanceled() || token != generation) {
                    return Status.CANCEL_STATUS;
                }
                PriceIndex index = loadIndex();
                if (monitor.isCanceled() || token != generation) {
                    return Status.CANCEL_STATUS;
                }
                Display display = Display.getDefault();
                if (display == null || display.isDisposed()) {
                    return Status.OK_STATUS;
                }
                display.asyncExec(() -> {
                    if (panel == null || panel.isDisposed() || token != generation) {
                        return;
                    }
                    panel.show(index);
                });
                return Status.OK_STATUS;
            }
        };
        job.schedule();
    }

    private static PriceIndex loadIndex() {
        try {
            return RatesClient.fromEnvironment().load(uiLocale());
        } catch (RuntimeException exception) {
            String message = exception.getMessage() == null ? "The API URL was rejected." : exception.getMessage();
            try {
                PriceIndex bundled = Snapshot.load();
                return new PriceIndex(
                        bundled.cities(),
                        bundled.asOf(),
                        bundled.attribution(),
                        bundled.licenseUrl(),
                        Origin.SNAPSHOT,
                        message);
            } catch (RatesException snapshotError) {
                return new PriceIndex(java.util.List.of(), null, null, null, Origin.SNAPSHOT, message);
            }
        }
    }

    static String uiLocale() {
        String nl = Platform.getNL();
        return RatesClient.normalizeLocale(nl);
    }
}
