import numpy as np, math
for eta in [.43,.57,.71,.85]:
 t=np.linspace(0,2*np.pi,400); d=1-np.sin(eta)*np.sin(t)
 pts=np.array([np.cos(eta)*np.cos(t)/d,np.cos(eta)*np.sin(t)/d,np.sin(eta)*np.cos(t)/d]).T
 center=np.linalg.lstsq(np.c_[2*pts,np.ones(len(pts))],(pts*pts).sum(axis=1),rcond=None)[0][:3]
 rad=np.linalg.norm(pts-center,axis=1)
 print('Hopf fiber eta',eta,'radius',round(rad.mean(),3),'circle residual',float(rad.std()))
