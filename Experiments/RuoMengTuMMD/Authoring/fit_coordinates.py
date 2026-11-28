import math
from mathutils import Vector
def interp(x,points):
 if x<=points[0][0]:a,b=points[:2]
 elif x>=points[-1][0]:a,b=points[-2:]
 else:
  for a,b in zip(points,points[1:]):
   if a[0]<=x<=b[0]:break
 return a[1]+(b[1]-a[1])*(x-a[0])/(b[0]-a[0])

def headwarp(p):
 x,y,z=p;z2=interp(z,[(1.25,1.475),(1.286,1.512),(1.350,1.580),(1.3697,1.607),(1.397,1.643),(1.422,1.674),(1.501,1.820)])
 jaw=max(0,min(1,(1.365-z)/.06));mouth=math.exp(-((z-1.323)/.013)**4-(x/.035)**4)*max(0,min(1,(-y-.04)/.04));return Vector((x*1.40*(1-.06*jaw)*(1-.20*mouth),y*1.38,z2))

SHOULDER=.080927;ELBOW=.326231;WRIST=.545590;ARM_Z=1.216136;ARM_Y=.0208
targets={s:[Vector((s*.158,.018,1.414)),Vector((s*.276,.018,1.185)),Vector((s*.369,.018,.982))] for s in [-1,1]}
def armwarp(p,sign):
 x,y,z=p;x*=sign;sh,el,wr=targets[sign]
 if x<ELBOW:q=(x-SHOULDER)/(ELBOW-SHOULDER);center=sh+(el-sh)*q;direction=(el-sh).normalized()
 else:
  d=(x-ELBOW) if x<=WRIST else (WRIST-ELBOW)+(x-WRIST)*.82
  q=d/(WRIST-ELBOW);center=el+(wr-el)*q;direction=(wr-el).normalized()
 across=Vector((-direction.z*sign,0,direction.x*sign));normal=Vector((0,1,0));dz=z-ARM_Z;dy=y-ARM_Y
 # Neutral palm faces forward. Twist is progressively distributed along forearm.
 t=max(0,min(1,(x-(WRIST-.065))/.065));angle=math.pi/2*t
 dy2=dy*math.cos(angle)+dz*math.sin(angle);dz2=-dy*math.sin(angle)+dz*math.cos(angle)
 return center+normal*dy2+across*dz2

def bodywarp(p,armweight=0):
 x,y,z=p
 if armweight>.15 and abs(x)>.07:return armwarp(p,1 if x>=0 else -1)
 z2=interp(z,[(0,0),(.1155,.125),(.50084,.49),(.66,.86),(.84392,1.00),(.8794,1.04),(1.10,1.26),(1.216,1.414),(1.2486,1.470),(1.28,1.510)])
 return Vector((x*(1.20 if z<.90 else 1.40),y*1.10,z2))
