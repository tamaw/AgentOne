from PIL import Image
import subprocess,os,json,hashlib
p='/workspace/artifacts/wallpaper-challenge/'
raw=p+'final-raw.png'
im=Image.open(raw);im.load()
if im.size!=(3840,2160):raise RuntimeError('Incorrect native render resolution')
subprocess.run(['python3',p+'compose.py',raw,p+'final.png'],check=True)
f=Image.open(p+'final.png');f.load()
if f.size!=(3840,2160) or f.mode!='RGB':raise RuntimeError('Incorrect final PNG')
with open(p+'final-audit.json','w') as out:subprocess.run(['python3',p+'final-audit.py',p+'final.png'],stdout=out,check=True)
with open(p+'final-noise-audit.txt','w') as out:subprocess.run(['python3',p+'noise-audit.py',raw],stdout=out,check=True)
thumb=f.copy();thumb.thumbnail((1280,720),Image.Resampling.LANCZOS);thumb.save(p+'preview.png')
print('FINAL_VERIFIED',f.size,f.mode,hashlib.sha256(open(p+'final.png','rb').read()).hexdigest())
