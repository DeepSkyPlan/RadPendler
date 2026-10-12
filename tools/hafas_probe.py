"""Haltestellen bei der VBB-API nachschlagen: python3 tools/hafas_probe.py "S Wannsee" …

Liest die Access-ID aus Secrets.xcconfig (lokal) und gibt sie nie aus.
"""
import json, pathlib, re, subprocess, sys, urllib.parse

BASE = "https://fahrinfo.vbb.de/restproxy/latest"
ROOT = pathlib.Path(__file__).resolve().parent.parent


def access_id():
    m = re.search(r"^VBB_ACCESS_ID *= *(\S+)", (ROOT / "Secrets.xcconfig").read_text(), re.M)
    if not m:
        sys.exit("VBB_ACCESS_ID fehlt in Secrets.xcconfig")
    return m.group(1)


def call(service, **params):
    params.update(format="json", lang="de")
    url = f"{BASE}/{service}?{urllib.parse.urlencode(params)}"
    out = subprocess.run(["curl", "-s", "-m", "40", "-H", f"Authorization: Bearer {access_id()}", url],
                         capture_output=True).stdout
    return json.loads(out)


if __name__ == "__main__":
    for q in sys.argv[1:]:
        res = call("location.name", input=q, maxNo=4)
        if "errorCode" in res:
            sys.exit(f"{res['errorCode']}: {res.get('errorText')}")
        for entry in res.get("stopLocationOrCoordLocation", []):
            for kind, l in entry.items():
                print(q, "->", kind, l["name"], l.get("lat"), l.get("lon"), l.get("extId", ""), l.get("products", ""))
