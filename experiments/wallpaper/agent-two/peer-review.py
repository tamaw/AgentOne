from PIL import Image
import urllib.request,os
root='/workspace/artifacts/wallpaper-challenge/'
for name in ['initial.png','preview.png']:
 try:
  data=urllib.request.urlopen('http://agent-one:43123/'+name,timeout=5).read()
  fn=root+'peer-'+name;open(fn,'wb').write(data)
  im=Image.open(fn);im.verify();print('PEER_ARTIFACT_READY',fn)
 except Exception as e: print('PEER_ARTIFACT_NOT_READY',name,str(e))
