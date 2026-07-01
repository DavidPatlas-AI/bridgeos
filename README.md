# BRIDGE OS — שולחן העבודה

**Bridge OS** is a local "second brain" desktop workspace: a 3D map of worlds and projects, Hebrew thread labels, per-project agent terminals, portfolio sync, Netlify analytics, and MCP integration for Claude / Cursor.

עברית: מערכת מקומית לניהול פרויקטים — מפת 3D, חוטים בעברית, סוכן לכל פרויקט, חיבור לפורטפוליו ו-MCP.

## Quick start

1. Double-click `שולחן עבודה.bat` on the Desktop (or `הפעל שולחן עבודה.bat` in this folder).
2. Open **http://127.0.0.1:8787/** — do not open `index.html` directly (needs the local server).
3. Open the product guide at **http://127.0.0.1:8787/landing.html** or run `פתח אתר הסבר.bat`.
4. To create a clean portable ZIP, run `יצירת חבילת הורדה.bat`.
5. To scan broken paths and launchers, run `בדיקת בריאות.bat`.

## Features (v2.1)

- **3D brain map** — 6 worlds, 10 glowing threads with Hebrew labels
- **Project agents** — click a project → terminal + `BRIDGE_SESSION.md` for Claude
- **Portfolio sync** — bidirectional GitHub/demo/desc sync with `portfolio.html`
- **Netlify Analytics** — 7d/30d pageviews per live site (requires token)
- **Transparent overlay** — `הפעל overlay שקוף.bat` (pywebview + WebView2)
- **Product guide** — `landing.html` explains the idea, download, and usage in simple Hebrew
- **Portable package** — `dist/BridgeOS-portable.zip` excludes personal config/tokens
- **Health check** — `בדיקת בריאות.bat` writes `BRIDGE_HEALTH_REPORT.md`
- **Rainmeter** — `התקן Rainmeter חוטים.bat`
- **MCP server** — `bridge-mcp-server.py` for Cursor / Claude Code
- **Ecosystem panel** — recent-files (8082), status map, config UI

## MCP setup

```bash
py -3.12 -m pip install -r requirements-mcp.txt
```

Add to Cursor MCP settings (see `mcp-config.json`):

```json
{
  "mcpServers": {
    "bridge-os": {
      "command": "py",
      "args": ["-3.12", "C:\\Users\\DAVID\\Desktop\\BridgeOS\\bridge-mcp-server.py"],
      "env": { "BRIDGE_PORT": "8787" }
    }
  }
}
```

**Tools:** `bridge_list_projects`, `bridge_open_terminal`, `bridge_dashboard`, `bridge_metrics`, `bridge_netlify`, `bridge_sync_portfolio`, `bridge_get_project`

## Config (optional)

Copy `bridge-config.example.json` → `bridge-config.json`:

- `github.token` — repo metrics (public_repo read)
- `netlify.token` — Analytics API (requires Analytics per site)
- `portfolioPath` — override auto-detected portfolio path

## API (local)

| Endpoint | Description |
|----------|-------------|
| `GET /api/info` | Version, portfolio, netlify configured |
| `GET /api/dashboard` | Stats + pageviews |
| `GET /api/ecosystem` | Recent-files + status map status |
| `GET /api/health` | Server, shortcut, tool, MCP, status map and project path health |
| `GET /api/recent/{id}` | Recent files for project path |
| `GET/POST /api/config` | Read/save bridge-config.json |
| `GET /api/metrics` | GitHub + live + Netlify |
| `POST /api/sync-portfolio` | Sync with portfolio |
| `GET /open/{id}` | Open terminal session |

## Structure

```
BridgeOS/
  index.html           — 3D UI + panels
  landing.html         — product guide + download page
  bridge.ps1           — HTTP server :8787 + API
  bridge-mcp-server.py — MCP stdio server
  bridge-data.json     — worlds, threads, projects
  assets/              — product preview image
  dist/                — generated portable ZIP
  scripts/             — packaging and helper scripts
  BRIDGE_HEALTH_REPORT.md — latest local scan result
  terminals/           — p1.bat … p7.bat
  lib/three.min.js     — offline 3D
```

## Requirements

- Windows 10+
- PowerShell 5.1+ (built-in)
- Python 3.12 (MCP + overlay only)
- Bridge OS server running for UI and MCP

## License

MIT — see [LICENSE](LICENSE)
