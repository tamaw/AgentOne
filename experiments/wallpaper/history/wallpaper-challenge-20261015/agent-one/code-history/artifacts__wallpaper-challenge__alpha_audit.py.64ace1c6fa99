import sys,numpy as np
from PIL import Image
for p in sys.argv[1:]:
 a=np.asarray(Image.open(p).convert('RGBA'))[:,:,3]/255.;ys,xs=np.where(a>.25);h,w=a.shape
 print(p.split('/')[-1], 'ALPHA_BOUNDS',np.round([xs.min()/w,xs.max()/w,ys.min()/h,ys.max()/h],4),'occupancy',round((a>.25).mean(),4))
