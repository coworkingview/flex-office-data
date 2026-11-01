import streamDeck from "@elgato/streamdeck";

import { MarketRateAction } from "./actions/market-rate.ts";
import { WorkspaceCountAction } from "./actions/workspace-count.ts";
import { setApiLogger } from "./api.ts";
import { REFRESH_INTERVAL_MS } from "./settings.ts";

setApiLogger((message) => {
	streamDeck.logger.info(message);
});

const workspaceCount = new WorkspaceCountAction();
const marketRate = new MarketRateAction();

streamDeck.actions.registerAction(workspaceCount);
streamDeck.actions.registerAction(marketRate);

const refreshTimer = setInterval(() => {
	void workspaceCount.refreshAll();
	void marketRate.refreshAll();
}, REFRESH_INTERVAL_MS);
refreshTimer.unref();

streamDeck.connect();
