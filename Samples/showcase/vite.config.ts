// Copyright (c) Cratis. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// The showcase listens on :4002. Everything Arc owns is proxied to it, WebSockets included, so the
// browser sees one origin and there is no CORS to configure. `npm run build` writes into the
// server's `priv/spa`, and then the server serves the app itself on the same origin.
const backend = process.env.ARC_BACKEND ?? 'http://localhost:4002';

// The app shell is in `frontend`. Each feature's React code is beside its Elixir, in `lib`.
export default defineConfig({
    root: 'frontend',
    plugins: [react()],
    server: {
        port: Number(process.env.ARC_FRONTEND_PORT ?? 5174),
        strictPort: true,
        proxy: {
            '/api': { target: backend, changeOrigin: true, ws: true },
            '/.cratis': { target: backend, changeOrigin: true, ws: true }
        }
    },
    build: {
        outDir: '../priv/spa',
        emptyOutDir: true
    }
});
