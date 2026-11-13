#!/usr/bin/env python3
from pathlib import Path

web = Path("Web/index.html").read_text(encoding="utf-8")
native = Path("ERIHost/HostApp.swift").read_text(encoding="utf-8")
project = Path("project.yml").read_text(encoding="utf-8")

for token in ("__eriReceive", "native_bridge_unavailable", "setFeature", "getState", "reset",
              "window.webkit", "thirdParty"):
    if token != "thirdParty":
        assert token in web, f"Missing JS API: {token}"
for token in ('handlerName = "eri"', '"setFeature"', '"getState"', '"reset"', '"thirdPartyGameConnected": false'):
    assert token in native, f"Missing native API: {token}"
assert "ERIHost" in project
print("ERI WebView/native protocol static checks passed.")
