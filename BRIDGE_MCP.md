# BRIDGE MCP - Claude Code / Cursor

> Updated: 2026-07-01 09:42 - http://127.0.0.1:8787/

## MCP server (stdio)
1. pip install -r requirements-mcp.txt  (Python 3.12: py -3.12 -m pip install mcp)
2. Start Bridge OS: run shulchan-avoda.bat from Desktop
3. Add to Cursor/Claude MCP settings from: C:\Users\DAVID\Desktop\פרויקטים\BridgeOS\mcp-config.json
4. Server script: C:\Users\DAVID\Desktop\פרויקטים\BridgeOS\bridge-mcp-server.py

### MCP tools
- bridge_list_projects
- bridge_open_terminal(project_id)
- bridge_dashboard
- bridge_metrics(refresh)
- bridge_netlify(refresh)
- bridge_sync_portfolio(direction)
- bridge_get_project(project_id)

### MCP resources
- bridge://data | bridge://map | bridge://export | bridge://mcp

## Files to read
- bridge-data.json - full state
- COMPARTMENT_MAP.md - active projects summary
- bridge-export.json - portfolio-friendly export

## HTTP API (local)
- GET /api/mcp - machine manifest
- GET /api/dashboard - stats
- GET /api/metrics - GitHub + Netlify deploy + pageviews
- GET /api/netlify - Analytics summary (7d/30d totals)
- GET /open/{projectId} - terminal + BRIDGE_SESSION.md

## Projects
- **הזורעים בבינה** (p1) 65% - open: /open/p1
- **מלאי משנת יוסף — Offline** (p2) 32% - open: /open/p2
- **תזה — מורים חרדים ו-AI** (p3) 82% - open: /open/p3
- **ספר הריבניצר — תרגום רוסי** (p4) 44% - open: /open/p4
- **מתמטיקה לחרדים** (p5) 90% - open: /open/p5
- **האלגוריתם שחזר בתשובה** (p6) 75% - open: /open/p6
- **מסלול רכב** (p7) 85% - open: /open/p7
