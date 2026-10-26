import math,json
a=.53;b=math.log((1+a)/(1-a))/(2*math.pi)+.016
for label,g,rib in [('initial',.155,.016),('revision',b,.008)]:
 gapt=math.exp(2*math.pi*g)*(1-a*(1+rib))-(1+a*(1+rib))
 print(label,'growth',g,'conservative rib-inclusive radial clearance/r',gapt,'valid',gapt>0)
