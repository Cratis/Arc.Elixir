// Copyright (c) Cratis. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// Phoenix runs on :4000 by default. Everything Arc owns is proxied to it, so the browser sees one
// origin and there is no CORS to configure - the same shape production has when Phoenix serves
// the built assets itself (see the sample README).
const backend = process.env.ARC_BACKEND ?? 'http://localhost:4000';

export default defineConfig({
    plugins: [react()],
    server: {
        port: Number(process.env.ARC_FRONTEND_PORT ?? 5173),
        strictPort: true,
        proxy: {
            '/api': { target: backend, changeOrigin: true, ws: true },
            '/.cratis': { target: backend, changeOrigin: true, ws: true }
        }
    },
    build: {
        // The Phoenix sample sets this to its priv/spa to serve the build from one origin.
        outDir: process.env.ARC_SPA_OUT ?? 'dist',
        emptyOutDir: true
    }
});
