from PIL import Image
import sys,statistics
im=Image.open(sys.argv[1]).convert('RGB');w,h=im.size
for label,box in [('left',(0,0,int(w*.28),h)),('top',(0,0,w,int(h*.15))),('sculpture',(int(w*.45),int(h*.2),int(w*.85),int(h*.8)))]:
 p=list(im.crop(box).getdata());l=sorted(.2126*r+.7152*g+.0722*b for r,g,b in p)
 print(label,'luminance percentiles',[(q,round(l[int((len(l)-1)*q)],2)) for q in [.1,.5,.9,.99]])
