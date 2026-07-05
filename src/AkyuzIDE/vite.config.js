import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import { defineConfig, loadEnv } from 'vite';
import electron from 'vite-plugin-electron/simple';
import monacoEditorPlugin from 'vite-plugin-monaco-editor';
export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, '.', '');
    return {
        plugins: [
            react(),
            tailwindcss(),
            monacoEditorPlugin.default({ languageWorkers: ['editorWorkerService'] }),
            ...(process.env.NO_ELECTRON !== '1' ? [electron({
                    main: {
                        entry: 'electron/main.ts',
                    },
                    preload: {
                        input: 'electron/preload.ts',
                    },
                    renderer: process.env.NODE_ENV === 'test'
                        ? undefined
                        : {},
                })] : []),
        ],
        define: {
            'process.env.GEMINI_API_KEY': JSON.stringify(env.GEMINI_API_KEY),
        },
        resolve: {
            alias: {
                '@': path.resolve(__dirname, '.'),
            },
        },
        server: {
            port: 3001,
            strictPort: true,
            host: true,
            // HMR is disabled in AI Studio via DISABLE_HMR env var.
            // Do not modify—file watching is disabled to prevent flickering during agent edits.
            hmr: process.env.DISABLE_HMR !== 'true',
            // Aynı origin üzerinden /api → backend (CORS/405 ve localhost:3000 vs :8000 ayrımı sorunlarını önler)
            proxy: {
                '/api': {
                    target: 'http://127.0.0.1:8001',
                    changeOrigin: true,
                },
            },
        },
    };
});
