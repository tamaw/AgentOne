import math,sys,json,hashlib,os,re
from PIL import Image
import numpy as np
scene=open('/workspace/artifacts/wallpaper-challenge/final-scene.py').read();a=float(re.search(r'FRACTION=([0-9.]+)',scene).group(1));b=math.log((1+a)/(1-a))/(2*math.pi)+.016;rib=.002
gap=math.exp(2*math.pi*b)*(1-a*(1+rib))-(1+a*(1+rib))
report={'tube_fraction':a,'growth':b,'growth_per_revolution':math.exp(2*math.pi*b),'conservative_coil_clearance_per_radius':gap,'turns':2.9}
if len(sys.argv)>1:
 f=sys.argv[1];im=Image.open(f);im.load();p=np.asarray(im.convert('RGB'),dtype=np.float32);l=p@np.array([.2126,.7152,.0722])
 report.update({'image':f,'size':im.size,'mode':im.mode,'file_bytes':os.path.getsize(f),'sha256':hashlib.sha256(open(f,'rb').read()).hexdigest(),'clip_fraction':float(np.mean(p.max(axis=2)>250)),'luminance_percentiles':np.quantile(l,[.1,.5,.9,.95,.99]).tolist(),'left_mean_RGB':p[:,:int(im.width*.35)].mean(axis=(0,1)).tolist()})
print(json.dumps(report,indent=2))
