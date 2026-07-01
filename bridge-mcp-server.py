#!/usr/bin/env python3
"""Bridge OS MCP server — stdio transport, proxies local HTTP API."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

from mcp.server.fastmcp import FastMCP

PORT = int(os.environ.get("BRIDGE_PORT", "8787"))
BASE = f"http://127.0.0.1:{PORT}"
ROOT = os.path.dirname(os.path.abspath(__file__))

mcp = FastMCP(
    "bridge-os",
    instructions=(
        "Bridge OS — David's universal desktop workspace. "
        "Use tools to list projects, open terminals, read metrics, sync portfolio. "
        "Requires bridge.ps1 running on port 8787 (שולחן עבודה.bat)."
    ),
)


def _get(path: str, timeout: int = 30) -> dict | list | str:
    req = urllib.request.Request(f"{BASE}{path}", method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw


def _post(path: str, timeout: int = 90) -> dict | list:
    req = urllib.request.Request(f"{BASE}{path}", method="POST", data=b"")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _read_file(name: str) -> str:
    path = os.path.join(ROOT, name)
    with open(path, encoding="utf-8") as f:
        return f.read()


def _fmt(data: object) -> str:
    if isinstance(data, str):
        return data
    return json.dumps(data, ensure_ascii=False, indent=2)


def _bridge_up() -> None:
    try:
        _get("/api/info", timeout=3)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise RuntimeError(
            f"Bridge OS not running at {BASE}. Start שולחן עבודה.bat first."
        ) from exc


@mcp.tool()
def bridge_list_projects() -> str:
    """List all Bridge OS projects with id, name, status, progress, path."""
    _bridge_up()
    data = _get("/api/data")
    lines = ["# Bridge OS projects", ""]
    for p in data.get("projects", []):
        pct = int(float(p.get("progress") or 0) * 100)
        gh = p.get("github") or ""
        demo = p.get("demo") or ""
        lines.append(f"## {p['id']} — {p['name']}")
        lines.append(f"- status: {p.get('status')} · progress: {pct}%")
        lines.append(f"- goal: {p.get('goal', '')}")
        if p.get("path"):
            lines.append(f"- path: {p['path']}")
        if gh:
            lines.append(f"- github: {gh}")
        if demo:
            lines.append(f"- demo: {demo}")
        lines.append("")
    return "\n".join(lines)


@mcp.tool()
def bridge_open_terminal(project_id: str) -> str:
    """Open Windows Terminal + BRIDGE_SESSION.md for project (e.g. p5, p6, p7)."""
    _bridge_up()
    result = _get(f"/open/{project_id}")
    return _fmt(result)


@mcp.tool()
def bridge_dashboard() -> str:
    """Summary: projects, active, threads, live sites, Netlify pageviews."""
    _bridge_up()
    return _fmt(_get("/api/dashboard"))


@mcp.tool()
def bridge_metrics(refresh: bool = False) -> str:
    """GitHub commits, live HTTP check, Netlify deploy + pageviews per project."""
    _bridge_up()
    path = "/api/metrics?refresh=1" if refresh else "/api/metrics"
    return _fmt(_get(path))


@mcp.tool()
def bridge_netlify(refresh: bool = False) -> str:
    """Netlify Analytics summary: 7d/30d pageviews per linked project."""
    _bridge_up()
    path = "/api/netlify?refresh=1" if refresh else "/api/netlify"
    return _fmt(_get(path))


@mcp.tool()
def bridge_sync_portfolio(direction: str = "both") -> str:
    """Bidirectional sync github/demo with portfolio.html. direction: both|from|to."""
    _bridge_up()
    d = direction.strip().lower() or "both"
    if d not in ("both", "from", "to"):
        d = "both"
    return _fmt(_post(f"/api/sync-portfolio?direction={d}"))


@mcp.tool()
def bridge_get_project(project_id: str) -> str:
    """Full details for one project by id (p1-p7)."""
    _bridge_up()
    data = _get("/api/data")
    for p in data.get("projects", []):
        if p.get("id") == project_id:
            return _fmt(p)
    return f"Project not found: {project_id}"


@mcp.resource("bridge://data")
def resource_data() -> str:
    """bridge-data.json — worlds, threads, projects."""
    try:
        return _fmt(_get("/api/data"))
    except (urllib.error.URLError, TimeoutError, OSError):
        return _read_file("bridge-data.json")


@mcp.resource("bridge://map")
def resource_map() -> str:
    """COMPARTMENT_MAP.md — active projects summary."""
    return _read_file("COMPARTMENT_MAP.md")


@mcp.resource("bridge://export")
def resource_export() -> str:
    """bridge-export.json — portfolio-friendly export."""
    return _read_file("bridge-export.json")


@mcp.resource("bridge://mcp")
def resource_mcp_doc() -> str:
    """BRIDGE_MCP.md — setup and API reference."""
    return _read_file("BRIDGE_MCP.md")


if __name__ == "__main__":
    mcp.run(transport="stdio")