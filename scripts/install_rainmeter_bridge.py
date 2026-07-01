# -*- coding: utf-8 -*-
"""Register BridgeThreads Rainmeter skin in Rainmeter.ini (UTF-16 LE)."""
import os

RM_INI = os.path.join(os.environ['APPDATA'], 'Rainmeter', 'Rainmeter.ini')
SECTION = '[BridgeThreads\\BridgeThreads]'
BLOCK = (
    '\n[BridgeThreads\\BridgeThreads]\n'
    'Active=1\n'
    'WindowX=40\n'
    'WindowY=120\n'
    'WindowW=80\n'
    'WindowH=40\n'
    'ClickThrough=0\n'
    'Draggable=1\n'
    'SnapEdges=1\n'
    'KeepOnScreen=1\n'
    'AlwaysOnTop=0\n'
)


def main():
    if not os.path.isfile(RM_INI):
        print('Rainmeter.ini not found:', RM_INI)
        return 1
    with open(RM_INI, encoding='utf-16') as f:
        content = f.read()
    if SECTION in content:
        print('BridgeThreads already registered')
        return 0
    with open(RM_INI, 'w', encoding='utf-16') as f:
        f.write(content.rstrip() + BLOCK)
    print('Registered BridgeThreads skin — Refresh Rainmeter (F5)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())