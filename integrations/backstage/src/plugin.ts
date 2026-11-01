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
  createComponentExtension,
  createPlugin,
  createRoutableExtension,
} from '@backstage/core-plugin-api';
import { rootRouteRef } from './routes';

/** Legacy frontend system plugin. New apps should use the `/alpha` export. */
export const coworkingViewPlugin = createPlugin({
  id: 'coworkingview',
  routes: {
    root: rootRouteRef,
  },
});

export const CoworkingViewPage = coworkingViewPlugin.provide(
  createRoutableExtension({
    name: 'CoworkingViewPage',
    component: () =>
      import('./components/CoworkingViewPage').then(m => m.CoworkingViewPage),
    mountPoint: rootRouteRef,
  }),
);

export const CoworkingViewCard = coworkingViewPlugin.provide(
  createComponentExtension({
    name: 'CoworkingViewCard',
    component: {
      lazy: () => import('./components/CoworkingViewCard').then(m => m.CoworkingViewCard),
    },
  }),
);
