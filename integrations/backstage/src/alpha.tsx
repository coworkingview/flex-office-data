/*
 * Copyright 2026 CoworkingView
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {
  createFrontendPlugin,
  createRouteRef,
  PageBlueprint,
} from '@backstage/frontend-plugin-api';

const rootRouteRef = createRouteRef();

function CoworkingViewIcon() {
  return (
    <svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor" aria-hidden="true">
      <path d="M4 20V9l8-5 8 5v11h-5v-6H9v6H4z" />
    </svg>
  );
}

const coworkingViewPage = PageBlueprint.make({
  params: {
    path: '/coworkingview',
    title: 'CoworkingView',
    icon: <CoworkingViewIcon />,
    routeRef: rootRouteRef,
    noHeader: true,
    loader: () =>
      import('./components/CoworkingViewPage').then(m => <m.CoworkingViewPage />),
  },
});

/** New frontend system plugin. Install the package, or pass this default export to `createApp`. */
export default createFrontendPlugin({
  pluginId: 'coworkingview',
  title: 'CoworkingView',
  info: {
    packageJson: () => import('../package.json'),
  },
  extensions: [coworkingViewPage],
  routes: {
    root: rootRouteRef,
  },
});
