import numpy as np,sys,json
from PIL import Image
im=np.array(Image.open(sys.argv[1]).convert('RGBA')); a=im[:,:,3]; h,w=a.shape
m=a>128; y,x=np.nonzero(m)
xy=np.column_stack((x/w,y/h));cov=np.cov(xy.T);v=np.linalg.eigvalsh(cov)
print('STRUCTURE',json.dumps({'coverage':float(m.mean()),'bounds':[float(x.min()/w),float(y.min()/h),float(x.max()/w),float(y.max()/h)],'anisotropy':float(v[1]/v[0]),'center':xy.mean(axis=0).tolist()}))
for row in range(24):
 print(''.join('█' if a[min(h-1,int((row+.5)*h/24)),min(w-1,int((col+.5)*w/80))]>128 else ' ' for col in range(80)))
