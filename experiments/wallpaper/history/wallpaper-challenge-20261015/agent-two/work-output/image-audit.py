from PIL import Image,ImageStat,ImageFilter
import sys,math,json
im=Image.open(sys.argv[1]).convert('RGB')
print('IMAGE',sys.argv[1],im.size)
s=im.resize((100,45)); chars=' .,:;irsXA253hMHGS#9B&@'
for y in range(s.height):
 print(''.join(chars[min(len(chars)-1,int((.2126*r+.7152*g+.0722*b)/255*(len(chars)-1)))] for r,g,b in [s.getpixel((x,y)) for x in range(s.width)]))
w,h=im.size; pix=im.load(); active=[]; bright=0; clipped=0
for y in range(0,h,4):
 for x in range(0,w,4):
  r,g,b=pix[x,y]; lum=.2126*r+.7152*g+.0722*b
  if lum>55: active.append((x,y,lum))
  if lum>210: bright+=1
  if max(r,g,b)>250: clipped+=1
n=math.ceil(w/4)*math.ceil(h/4)
if active:
 total=sum(p[2] for p in active)
 print('LIT_BOUNDS',tuple(round(v,3) for v in (min(p[0] for p in active)/w,min(p[1] for p in active)/h,max(p[0] for p in active)/w,max(p[1] for p in active)/h)))
 print('LIT_CENTROID',round(sum(x*l for x,y,l in active)/total/w,3),round(sum(y*l for x,y,l in active)/total/h,3))
print('COVERAGE',round(len(active)/n,4),'BRIGHT',round(bright/n,4),'CLIP',round(clipped/n,4))
for j in range(3):
 print('REGION_ROW',j,[tuple(round(v,1) for v in ImageStat.Stat(im.crop((i*w//4,j*h//3,(i+1)*w//4,(j+1)*h//3))).mean) for i in range(4)])
