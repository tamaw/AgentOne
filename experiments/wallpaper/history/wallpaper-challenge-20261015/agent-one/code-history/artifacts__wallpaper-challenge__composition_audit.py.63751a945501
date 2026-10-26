from PIL import Image
import numpy as np,sys
for path in sys.argv[1:]:
 a=np.asarray(Image.open(path).convert('RGB'),dtype=float)/255; lum=a@np.array([.2126,.7152,.0722]); h,w=lum.shape
 mask=lum>.22; yy,xx=np.nonzero(mask); print(path,'bright coverage',round(mask.mean(),4),'centroid',tuple(round(v,3) for v in (xx.mean()/w,yy.mean()/h)))
 print('left quarter median',round(np.median(lum[:,:w//4]),3),'right',round(np.median(lum[:,3*w//4:]),3),'top',round(np.median(lum[:h//4]),3),'bottom',round(np.median(lum[3*h//4:]),3))
 print('color mean of bright fibers',np.round(a[mask].mean(axis=0),3))
