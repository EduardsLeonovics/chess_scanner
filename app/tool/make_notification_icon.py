"""Makes the Android status-bar icon (white on transparent) from the app icon.

Android draws a notification's small icon as a flat silhouette of its alpha,
so the full-colour launcher icon shows up as a solid square. This keeps only
the magnifier and knight. Run from app/: python tool/make_notification_icon.py
"""
from PIL import Image, ImageDraw
SS=4
src=Image.open('assets/icon/app_icon_foreground.png').convert('RGBA')
W=src.width
cx,cy,ro,ri=510,490,129,107
mask=Image.new('L',(W*SS,W*SS),0)
d=ImageDraw.Draw(mask)
d.ellipse([(cx-ro)*SS,(cy-ro)*SS,(cx+ro)*SS,(cy+ro)*SS],fill=255)
d.ellipse([(cx-ri)*SS,(cy-ri)*SS,(cx+ri)*SS,(cy+ri)*SS],fill=0)
# handle
x0,y0,x1,y1,w=598,578,698,678,30
d.line([x0*SS,y0*SS,x1*SS,y1*SS],fill=255,width=w*SS)
r=w//2
d.ellipse([(x1-r)*SS,(y1-r)*SS,(x1+r)*SS,(y1+r)*SS],fill=255)
mask=mask.resize((W,W),Image.LANCZOS)
# knight: white pixels inside the lens
px=src.load(); m=mask.load()
for y in range(cy-ri,cy+ri):
    for x in range(cx-ri,cx+ri):
        if (x-cx)**2+(y-cy)**2 < (ri-3)**2:
            p=px[x,y]
            whiteness=min(p[0],p[1])  # blue has low red
            m[x,y]=max(0,min(255,int((whiteness-80)*255/(230-80))))
# square crop around lens+handle with padding
left,top,right,bottom=cx-ro,cy-ro,x1+r,y1+r
side=max(right-left,bottom-top); pad=int(side*0.06)
box=(left-pad,top-pad,left-pad+side+2*pad,top-pad+side+2*pad)
mask=mask.crop(box)
out=Image.new('RGBA',mask.size,(255,255,255,0)); out.putalpha(mask)
for name,px_ in {'mdpi':24,'hdpi':36,'xhdpi':48,'xxhdpi':72,'xxxhdpi':96}.items():
    out.resize((px_,px_),Image.LANCZOS).save(f'android/app/src/main/res/drawable-{name}/ic_stat_notification.png')
