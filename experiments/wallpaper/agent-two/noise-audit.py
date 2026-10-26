import numpy as np,sys,json
from PIL import Image
raw=Image.open(sys.argv[1]).convert('RGBA');a=np.array(raw.getchannel('A'))/255
p=np.asarray(raw.convert('RGB'),dtype=np.float32);lum=p@np.array([.2126,.7152,.0722])
c=lum[1:-1,1:-1];n=(lum[:-2,1:-1]+lum[2:,1:-1]+lum[1:-1,:-2]+lum[1:-1,2:])/4
grad=np.maximum(np.abs(lum[1:-1,2:]-lum[1:-1,:-2]),np.abs(lum[2:,1:-1]-lum[:-2,1:-1]))
flat=(grad<4)&(a[1:-1,1:-1]>.99)&(c>40)&(c<160)
res=(c-n)[flat]
print('NOISE_AUDIT',json.dumps({'file':sys.argv[1],'flat_interior_pixels':int(flat.sum()),'laplacian_residual_abs_median':float(np.median(np.abs(res))),'laplacian_residual_abs_p95':float(np.quantile(np.abs(res),.95)),'method':'flat opaque interior only; curvature/texture may contribute, not pure noise estimate'}))
w,h=raw.size
for name,cx,cy in [('outer',(0.52),(0.45)),('inner',.66,.47),('lip',.72,.32)]:
 x=int(cx*w);y=int(cy*h);s=min(256,w//4)
 raw.crop((x-s//2,y-s//2,x+s//2,y+s//2)).save(sys.argv[1].replace('.png','-crop-'+name+'.png'))
