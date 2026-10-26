import numpy as np

def fiber(eta,phi,n=201):
 t=np.linspace(0,2*np.pi,n);d=1-np.sin(eta)*np.sin(t)
 return np.array([np.cos(eta)*np.cos(t+phi)/d,np.cos(eta)*np.sin(t+phi)/d,np.sin(eta)*np.cos(t)/d]).T
eta=.72;N=24;r=.027; fs=[fiber(eta,2*np.pi*k/N) for k in range(N)]
gap=min(np.sqrt(((fs[a][:,None,:]-fs[b][None,:,:])**2).sum(axis=2).min()) for a in range(N) for b in range(a+1,N))
print('FIBER CLEARANCE: sampled centerline min',gap,'tube diameter',2*r,'surface clearance',gap-2*r)
print('Extent',np.round(np.concatenate(fs).min(axis=0),3),np.round(np.concatenate(fs).max(axis=0),3))
assert gap>2*r
