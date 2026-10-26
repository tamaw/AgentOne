from PIL import Image
import numpy as np,sys,json
def audit(path):
 im=Image.open(path);a=np.asarray(im.convert('RGB'),dtype=float)/255;h,w=a.shape[:2];lum=a@np.array([.2126,.7152,.0722]);mask=lum>.22;ys,xs=np.where(mask)
 result={'file':path,'dimensions':[w,h],'format':im.format,'mode':im.mode,'finite':bool(np.isfinite(a).all()),'highlight_clipping_fraction':float((a.max(2)>.995).mean()),'lit_coverage':float(mask.mean()),'luminance_percentiles':np.percentile(lum,[5,50,95,99]).tolist(),'left_quarter_luminance_median':float(np.median(lum[:,:w//4]))}
 if len(xs):result.update(lit_bounds=[float(xs.min()/w),float(xs.max()/w),float(ys.min()/h),float(ys.max()/h)],lit_centroid=[float(xs.mean()/w),float(ys.mean()/h)])
 return result
if __name__=='__main__':
 for path in sys.argv[1:]:print(json.dumps(audit(path)))
