package com.coworkingview.eclipse;

import java.nio.file.Files;
import java.nio.file.Path;

import org.eclipse.swt.SWT;
import org.eclipse.swt.custom.CTabFolder;
import org.eclipse.swt.custom.CTabItem;
import org.eclipse.swt.graphics.GC;
import org.eclipse.swt.graphics.Image;
import org.eclipse.swt.graphics.ImageData;
import org.eclipse.swt.graphics.ImageLoader;
import org.eclipse.swt.layout.FillLayout;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Shell;
import org.junit.Test;

/**
 * Renders the view composite under a real SWT display. Not part of the default test run.
 * Invoke with {@code mvn -Pscreenshot verify} and {@code xvfb-run}.
 */
public class CapturePricesView {

    @Test
    public void capture() throws Exception {
        Path directory = Path.of("../docs/screenshots").toAbsolutePath();
        Files.createDirectories(directory);
        PriceIndex index = new RatesClient(RatesClient.DEFAULT_BASE, java.time.Duration.ofSeconds(20)).load("en");
        Display display = new Display();
        try {
            Shell shell = new Shell(display);
            shell.setLayout(new FillLayout());
            shell.setText("CoworkingView Workspace Prices");
            CTabFolder folder = new CTabFolder(shell, SWT.BORDER);
            CTabItem tab = new CTabItem(folder, SWT.NONE);
            tab.setText("CoworkingView Workspace Prices");
            PricesPanel panel = new PricesPanel(folder, SWT.NONE, () -> { });
            tab.setControl(panel);
            folder.setSelection(tab);
            shell.setSize(1180, 860);
            shell.open();
            panel.show(index);
            drain(display);
            if (panel.visibleRowCount() < 1) {
                throw new IllegalStateException("The view rendered no cities.");
            }
            save(display, shell, directory.resolve("workspace-prices.png"));

            panel.setFilterText("Berlin");
            drain(display);
            if (panel.visibleRowCount() != 1) {
                throw new IllegalStateException("Berlin filter showed " + panel.visibleRowCount() + " rows.");
            }
            save(display, shell, directory.resolve("workspace-prices-berlin.png"));
            shell.dispose();
        } finally {
            display.dispose();
        }
    }

    private static void drain(Display display) {
        for (int i = 0; i < 30; i++) {
            while (display.readAndDispatch()) {
                // apply layout and paint
            }
            display.update();
        }
    }

    private static void save(Display display, Shell shell, Path path) throws Exception {
        shell.layout(true, true);
        drain(display);
        Image image = new Image(display, shell.getSize().x, shell.getSize().y);
        GC gc = new GC(image);
        try {
            shell.print(gc);
        } finally {
            gc.dispose();
        }
        ImageLoader loader = new ImageLoader();
        loader.data = new ImageData[] { image.getImageData() };
        loader.save(path.toString(), SWT.IMAGE_PNG);
        image.dispose();
        if (Files.size(path) < 5_000) {
            throw new IllegalStateException("Screenshot is unexpectedly small: " + path);
        }
    }
}
