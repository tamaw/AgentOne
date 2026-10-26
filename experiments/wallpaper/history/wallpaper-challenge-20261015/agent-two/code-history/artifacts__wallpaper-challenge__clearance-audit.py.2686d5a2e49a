import re,math,json
s=open('/workspace/artifacts/wallpaper-challenge/final-scene.py').read();a=float(re.search(r'FRACTION=([0-9.]+)',s).group(1));b=math.log((1+a)/(1-a))/(2*math.pi)+.016;T=5.8*math.pi
r0=3.55/math.exp(b*T);rib=.002;clear=math.exp(2*math.pi*b)*(1-a*(1+rib))-(1+a*(1+rib))
minimum=r0*clear;solidify=.025;lip=.026
report={'inner_centerline_radius':r0,'outer_centerline_radius':3.55,'rib_inclusive_radial_clearance_min':minimum,'membrane_thickness':solidify,'copper_lip_diameter':2*lip,'conservative_gap_after_two_lips':minimum-2*lip,'clearance_positive':minimum>2*lip,'method':'adjacent-turn radial annulus clearance; conservative over t and rib displacement, not a complete arbitrary-surface intersection proof'}
assert minimum>2*lip
print(json.dumps(report,indent=2))
open('/workspace/artifacts/wallpaper-challenge/clearance-audit.json','w').write(json.dumps(report,indent=2))
