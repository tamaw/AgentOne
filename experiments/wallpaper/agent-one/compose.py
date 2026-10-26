from PIL import Image,ImageFilter
import numpy as np,sys
source,dest=sys.argv[1:3]; im=Image.open(source).convert('RGBA'); w,h=im.size
y,x=np.mgrid[0:h,0:w]; x=x/w;y=y/h
spot=np.exp(-((x-.61)**2/.12+(y-.42)**2/.25)); rim=np.exp(-((x-.18)**2/.20+(y-.8)**2/.2))
base=np.zeros((h,w,3)); base[:]=[5,12,20]; base+=spot[:,:,None]*np.array([6,16,19]);base+=rim[:,:,None]*np.array([2,5,7])
rng=np.random.default_rng(71);base+=rng.uniform(-.4,.4,(h,w,1))
bg=Image.fromarray(np.uint8(np.clip(base,0,255))).convert('RGBA'); bg=Image.alpha_composite(bg,im)
bg.convert('RGB').save(dest)
print('COMPOSITE: geometry alpha over controlled petrol field; background luminance bounded, resolution',w,h)
