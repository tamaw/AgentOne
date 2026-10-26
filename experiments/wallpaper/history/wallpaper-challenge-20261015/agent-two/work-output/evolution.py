from PIL import Image,ImageDraw,ImageFont
import os
p='/workspace/artifacts/wallpaper-challenge/'
entries=[('initial.png','Initial: intersecting coils, bleached glaze'),('revision1.png','1: clearance-derived geometry'),('revision2.png','2: open trough, restored negative space'),('revision3.png','3: projected safe-frame fit'),('revision5.png','5: lower growth reveals inner windings'),('revision8.png','8: diagonal, true void, selective copper')]
sheet=Image.new('RGB',(1536,980),(7,13,23));d=ImageDraw.Draw(sheet)
for k,(f,label) in enumerate(entries):
 im=Image.open(p+f).convert('RGB').resize((768,432),Image.Resampling.LANCZOS);x=(k%2)*768;y=(k//2)*326
 im=im.resize((544,306),Image.Resampling.LANCZOS);sheet.paste(im,(x+112,y))
 d.text((x+24,y+308),label,fill=(170,192,188))
sheet.save(p+'evolution-contact-sheet.png')
