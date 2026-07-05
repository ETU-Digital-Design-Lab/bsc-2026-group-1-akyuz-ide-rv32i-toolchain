import { app, BrowserWindow, shell, ipcMain, dialog } from 'electron';
import { autoUpdater } from 'electron-updater';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { spawn, spawnSync, ChildProcess } from 'node:child_process';
import net from 'node:net';
import fs from 'node:fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
let backendProcess: ChildProcess | null = null;

// Linux'ta AppImage sandbox sorunu — no-sandbox flag'i ekle
if (process.platform === 'linux') {
  app.commandLine.appendSwitch('no-sandbox');
}

// The built directory structure
// |- dist
// |- dist-electron
//   |- main.js
process.env.APP_ROOT = path.join(__dirname, '..');

// 🚧 Developer note: Customize the loading logic
export const VITE_DEV_SERVER_URL = process.env['VITE_DEV_SERVER_URL'];
export const MAIN_DIST = path.join(process.env.APP_ROOT, 'dist');
export const RENDERER_DIST = path.join(process.env.APP_ROOT, 'dist');

process.env.VITE_PUBLIC = VITE_DEV_SERVER_URL ? path.join(process.env.APP_ROOT, 'public') : RENDERER_DIST;

let win: BrowserWindow | null = null;
let splash: BrowserWindow | null = null;
let winReady = false;
let pendingUpdateAvailable: any = null;
let pendingUpdateDownloaded: any = null;

function createSplash() {
  splash = new BrowserWindow({
    width: 480,
    height: 300,
    frame: false,
    transparent: false,
    resizable: false,
    center: true,
    skipTaskbar: true,
    alwaysOnTop: true,
    backgroundColor: '#0a0e17',
    icon: path.join(process.env.VITE_PUBLIC, 'logo.png'),
    webPreferences: { nodeIntegration: false, contextIsolation: true },
  });

  const splashPath = VITE_DEV_SERVER_URL
    ? path.join(process.env.APP_ROOT!, 'public', 'splash.html')
    : path.join(RENDERER_DIST, 'splash.html');

  splash.loadFile(splashPath);
  splash.show();
}

function closeSplash() {
  if (splash && !splash.isDestroyed()) {
    splash.close();
    splash = null;
  }
}

function createWindow() {
  win = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    icon: path.join(process.env.VITE_PUBLIC, 'logo.png'),
    frame: false,
    titleBarStyle: 'hidden',
    backgroundColor: '#1e1e1e',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.mjs'),
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  win.webContents.on('did-finish-load', () => {
    closeSplash();
    win?.show();
    winReady = true;
    if (pendingUpdateAvailable) {
      win?.webContents.send('update-available', pendingUpdateAvailable);
      pendingUpdateAvailable = null;
    }
    if (pendingUpdateDownloaded) {
      win?.webContents.send('update-downloaded', pendingUpdateDownloaded);
      pendingUpdateDownloaded = null;
    }
  });

  if (VITE_DEV_SERVER_URL) {
    win.loadURL(VITE_DEV_SERVER_URL);
  } else {
    win.loadFile(path.join(RENDERER_DIST, 'index.html'));
  }

  // Open external links in browser
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  // Window Controls IPC
  ipcMain.on('window-control', (_, command) => {
    switch (command) {
      case 'minimize': win?.minimize(); break;
      case 'maximize': win?.isMaximized() ? win.unmaximize() : win?.maximize(); break;
      case 'close': win?.close(); break;
    }
  });

  ipcMain.handle('app-version', () => app.getVersion());

  ipcMain.handle('dialog:openFile', async () => {
    const { canceled, filePaths } = await dialog.showOpenDialog({
      properties: ['openFile']
    });
    if (canceled) return null;
    return filePaths[0];
  });

  ipcMain.handle('dialog:openDirectory', async () => {
    const { canceled, filePaths } = await dialog.showOpenDialog({
      properties: ['openDirectory']
    });
    if (canceled) return null;
    return filePaths[0];
  });
}

function spawnBackend() {
  const appRoot = process.env.APP_ROOT!;
  const serverRoot = appRoot.includes('app.asar')
    ? appRoot.replace('app.asar', 'app.asar.unpacked')
    : appRoot;
  const serverDir = path.join(serverRoot, 'server');
  const backendPath = path.join(serverDir, 'main.py');
  const workspaceDir = path.join(app.getPath('userData'), 'workspace');
  const venvDir = path.join(app.getPath('userData'), 'venv');
  const venvPython = path.join(venvDir, 'bin', 'python3');

  // Create venv and install requirements on first run
  if (!fs.existsSync(venvPython)) {
    console.log('[Main] Setting up Python environment (first run)...');
    spawnSync('python3', ['-m', 'venv', venvDir], { stdio: 'inherit' });
    const reqFile = path.join(serverDir, 'requirements.txt');
    spawnSync(venvPython, ['-m', 'pip', 'install', '-r', reqFile, '--quiet'], { stdio: 'inherit' });
  }

  console.log(`[Main] Spawning backend: ${venvPython} ${backendPath}`);
  backendProcess = spawn(venvPython, [backendPath], {
    cwd: serverDir,
    stdio: 'inherit',
    env: { ...process.env, WORKSPACE_DIR: workspaceDir }
  });

  backendProcess.on('error', (err) => {
    console.error('[Backend] Failed to start:', err);
  });

  backendProcess.on('exit', (code, signal) => {
    console.log(`[Backend] Exited (code=${code ?? 'null'}, signal=${signal ?? 'null'})`);
    backendProcess = null;
  });
}

function isPortOpen(host: string, port: number, timeoutMs = 700): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    let settled = false;

    const done = (result: boolean) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(result);
    };

    socket.setTimeout(timeoutMs);
    socket.once('connect', () => done(true));
    socket.once('timeout', () => done(false));
    socket.once('error', () => done(false));
    socket.connect(port, host);
  });
}

app.on('window-all-closed', () => {
  if (backendProcess) {
    console.log('[Main] Killing backend process...');
    backendProcess.kill();
  }
  if (process.platform !== 'darwin') {
    app.quit();
    win = null;
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});

async function waitForBackend(maxWaitMs = 15000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    if (await isPortOpen('127.0.0.1', 8001)) return;
    await new Promise(r => setTimeout(r, 300));
  }
}

function setupAutoUpdater() {
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = false;

  autoUpdater.on('error', (err) => {
    console.error('[Updater] Error:', err.message);
  });

  autoUpdater.on('update-available', (info) => {
    console.log('[Updater] Update available:', info.version);
    if (winReady && win && !win.isDestroyed()) {
      win.webContents.send('update-available', info);
    } else {
      pendingUpdateAvailable = info;
    }
  });

  autoUpdater.on('update-downloaded', (info) => {
    console.log('[Updater] Update downloaded:', info.version);
    if (winReady && win && !win.isDestroyed()) {
      win.webContents.send('update-downloaded', info);
    } else {
      pendingUpdateDownloaded = info;
    }
  });

  ipcMain.on('install-update', () => {
    autoUpdater.quitAndInstall();
  });

  ipcMain.on('check-for-updates', () => {
    autoUpdater.checkForUpdates().catch(() => {});
  });

  if (!VITE_DEV_SERVER_URL) {
    autoUpdater.checkForUpdates().catch(() => {});
  }
}

app.whenReady().then(async () => {
  createSplash();

  const backendAlreadyRunning = await isPortOpen('127.0.0.1', 8001);
  if (backendAlreadyRunning) {
    console.log('[Main] Backend already running on :8001, skip spawn.');
  } else {
    spawnBackend();
    console.log('[Main] Waiting for backend...');
    await waitForBackend();
  }
  createWindow();
  setupAutoUpdater();
});
