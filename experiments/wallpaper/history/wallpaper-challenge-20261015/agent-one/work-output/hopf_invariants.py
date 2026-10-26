import numpy as np
def fiber(eta,phi,n=600):
 t=np.arange(n)*2*np.pi/n;d=1-np.sin(eta)*np.sin(t)
 return np.array([np.cos(eta)*np.cos(t+phi)/d,np.cos(eta)*np.sin(t+phi)/d,np.sin(eta)*np.cos(t)/d]).T
def linking(a,b):
 da=np.roll(a,-1,axis=0)-a;db=np.roll(b,-1,axis=0)-b
 aa=(a+np.roll(a,-1,axis=0))/2;bb=(b+np.roll(b,-1,axis=0))/2
 delta=aa[:,None,:]-bb[None,:,:]
 return np.sum(np.einsum('ijk,ijk->ij',delta,np.cross(da[:,None,:],db[None,:,:]))/(np.linalg.norm(delta,axis=2)**3))/(4*np.pi)
if __name__=='__main__':
 for n in [200,400,800]:
  a=fiber(.5,0,n);b=fiber(.5,np.pi/3,n);print('GAUSS_LINK',n,linking(a,b))
 for eta in [.72,.5]:
  R=1/np.cos(eta);r=np.tan(eta);print('TORUS',eta,'major',R,'minor',r,'void_ratio',(R-r)/(R+r))
