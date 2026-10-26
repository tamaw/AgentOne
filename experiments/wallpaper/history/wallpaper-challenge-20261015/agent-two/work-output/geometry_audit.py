import math,json
b=.155; a=.53; turns=2.9
ratio=math.exp(2*math.pi*b)
minimum=math.log((1+a)/(1-a))/(2*math.pi)
gap=ratio*(1-a)-(1+a)
print(json.dumps({'growth_per_turn':ratio,'tube_fraction':a,'radial_gap_per_radius':gap,'minimum_nonintersecting_growth':minimum,'recommended_growth':minimum+.014},indent=2))
