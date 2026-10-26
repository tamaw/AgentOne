from PIL import Image
import numpy as np,sys
im=Image.open(sys.argv[1]).convert('RGB'); a=np.asarray(im)/255
lum=a@np.array([.2126,.7152,.0722]); print('Image',im.size,'luminance percentiles',np.percentile(lum,[1,25,50,75,95,99]))
print('Clipped pixels:',float(np.mean(np.max(a,axis=2)>.995)))
small=np.asarray(im.resize((96,36)))/255; g=small@np.array([.2126,.7152,.0722])
for row in g: print(''.join(' .,:;irsXA253hMHGS#9B&@'[min(21,int(x*22))] for x in row))
im.resize((960,540)).save(sys.argv[1].replace('.png','-thumb.png'))
