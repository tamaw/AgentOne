import numpy as np,sys,json
from PIL import Image,ImageFilter
src,dst=sys.argv[1:3]
im=Image.open(src).convert('RGBA');w,h=im.size
y,x=np.mgrid[0:h,0:w].astype(np.float32);x/=w;y/=h
base=np.array([7.5,13.5,23.5],dtype=np.float32)
halo=np.exp(-(((x-.66)/.37)**2+((y-.43)/.48)**2)*2)
sweep=np.exp(-(((x-.18)/.9)**2+((y-.86)/.7)**2)*2)
bg=base[None,None,:]+halo[:,:,None]*np.array([1.5,5.8,7.5])+sweep[:,:,None]*np.array([.7,1.8,2.9])
rng=np.random.default_rng(20261015);grain=rng.normal(0,.34,(h,w)).astype(np.float32)
bg+=grain[:,:,None]
back=Image.fromarray(np.uint8(np.clip(bg,0,255)),'RGB').convert('RGBA')
comp=Image.alpha_composite(back,im).convert('RGB')
comp.save(dst)
a=np.array(im.getchannel('A'));ys,xs=np.where(a>16)
print('COMPOSITION',json.dumps({'size':[w,h],'alpha_bounds':[float(xs.min()/w),float(ys.min()/h),float(xs.max()/w),float(ys.max()/h)],'alpha_coverage':float(np.mean(a>16)),'background_RGB_range':[bg.min(axis=(0,1)).tolist(),bg.max(axis=(0,1)).tolist()]}))
