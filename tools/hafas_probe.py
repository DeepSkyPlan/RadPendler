import json,sys,urllib.request
BASE={"lang":"de","client":{"type":"WEB","id":"VBB","name":"VBB WebApp","l":"vs_webapp_vbb"},"ext":"VBB.1","ver":"1.45","auth":{"type":"AID","aid":"hafas-vbb-webapp"}}
ENDPOINT="https://fahrinfo.vbb.de/bin/mgate.exe"
def call(meth,req):
    b=dict(BASE); b["svcReqL"]=[{"meth":meth,"req":req}]
    import subprocess
    out=subprocess.run(["curl","-s","-m","40","-H","Content-Type: application/json","--data-binary","@-","https://fahrinfo.vbb.de/bin/mgate.exe"],input=json.dumps(b).encode(),capture_output=True).stdout
    return json.loads(out)
if __name__=="__main__":
    for q in sys.argv[1:]:
        res=call("LocMatch",{"input":{"loc":{"type":"ALL","name":q},"maxLoc":4,"field":"S"}})
        for l in res["svcResL"][0]["res"]["match"]["locL"]: print(q,"->",l["type"],l["name"],l["crd"],l["lid"][:60])
