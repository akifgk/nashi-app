// Browser port of Sources/NashiApp/WheelGeometry.swift. Coordinates are flipped
// into SVG's downward Y axis; keep the native proportions and rounded petals.
export const SIZE = 320, RADIUS = SIZE * .44, INNER = RADIUS * .407;
const rad = degrees => degrees * Math.PI / 180;
export const point = (radius, degrees) => ({x:160 + radius*Math.cos(rad(degrees)), y:160 - radius*Math.sin(rad(degrees))});
export const angle = (count, index) => (count === 3 ? 180 : 90) - index*360/count;
const xy = p => `${p.x.toFixed(4)},${p.y.toFixed(4)}`;
export function petal(count, index) {
  const delta=360/count, mid=angle(count,index), a=mid-delta/2+.9, b=mid+delta/2-.9;
  const corner=Math.min(10,INNER*rad(delta)/4), oi=corner/RADIUS*180/Math.PI, ii=corner/INNER*180/Math.PI;
  const largeOuter=b-a-2*oi>180?1:0, largeInner=b-a-2*ii>180?1:0;
  return `M${xy(point(RADIUS-corner,a))} C${xy(point(RADIUS,a))} ${xy(point(RADIUS,a))} ${xy(point(RADIUS,a+oi))} A${RADIUS},${RADIUS} 0 ${largeOuter} 0 ${xy(point(RADIUS,b-oi))} C${xy(point(RADIUS,b))} ${xy(point(RADIUS,b))} ${xy(point(RADIUS-corner,b))} L${xy(point(INNER+corner,b))} C${xy(point(INNER,b))} ${xy(point(INNER,b))} ${xy(point(INNER,b-ii))} A${INNER},${INNER} 0 ${largeInner} 1 ${xy(point(INNER,a+ii))} C${xy(point(INNER,a))} ${xy(point(INNER,a))} ${xy(point(INNER+corner,a))} Z`;
}
export function labelCenters(count,index) {
  const sweep=rad(360/count-1.8), centroid=count>1?4*Math.sin(sweep/2)*(RADIUS**3-INNER**3)/(3*sweep*(RADIUS**2-INNER**2)):(RADIUS+INNER)/2;
  const preferred=centroid/RADIUS, fractions=[preferred];
  for(let step=1;step<=12;step++)fractions.push(preferred+step*.02,preferred-step*.02);
  const valid=fractions.filter(f=>f>INNER/RADIUS&&f<.86).concat([.73,.75,.71,.77,.69,.79,.67,.81]);
  const theta=rad(angle(count,index));
  return valid.flatMap(f=>[0,-4,4,-8,8].map(t=>({x:160+RADIUS*f*Math.cos(theta)-t*Math.sin(theta),y:160-RADIUS*f*Math.sin(theta)-t*Math.cos(theta)})));
}
function wrap(text,width,font,measure) {
  const lines=[];let line='';
  for(const word of text.split(/\s+/)) {
    if(measure(word,font).width>width)return null;
    const next=line?line+' '+word:word;
    if(line&&measure(next,font).width>width){lines.push(line);line=word;}else line=next;
  }
  if(line)lines.push(line);return lines;
}
export function containsRect(rect,contains,padding=3.5) {
  const x=rect.x-padding,y=rect.y-padding,w=rect.width+2*padding,h=rect.height+2*padding;
  for(let i=0;i<=8;i++) { const t=i/8;if(!contains(x+w*t,y)||!contains(x+w*t,y+h)||!contains(x,y+h*t)||!contains(x+w,y+h*t))return false; }
  return true;
}
// Fit the icon and each line separately inside the rounded path. This matters
// for wide, five-item PDF petals as well as long, eight-item Turkish labels.
export function fitLabel(count,index,title,hasIcon,measure,contains) {
  const centers=labelCenters(count,index),baseFont=hasIcon?9.5:13;
  for(let reduction=0;reduction<=3;reduction+=.25) {
    const font=baseFont-reduction;let best;
    for(let width=84;width>=36;width-=4) {
      const lines=wrap(title,width,font,measure);if(!lines)continue;
      const metrics=lines.map(line=>measure(line,font)), lineHeight=font*1.18;
      const textHeight=lines.length*lineHeight, height=textHeight+(hasIcon?24:0);
      for(let ci=0;ci<centers.length;ci++) {
        const center=centers[ci],top=center.y-height/2,rects=[];
        if(hasIcon)rects.push({x:center.x-10,y:top,width:20,height:20});
        metrics.forEach((m,j)=>rects.push({x:center.x-m.width/2,y:top+(hasIcon?24:0)+j*lineHeight,width:m.width,height:lineHeight}));
        if(!rects.every(r=>containsRect(r,contains)))continue;
        const score=lines.length*10+ci+(84-width)/84;
        const result={...center,font,lineHeight,height,lines,rects,width:Math.max(hasIcon?20:0,...metrics.map(m=>m.width)),fits:true};
        if(width===84&&ci===0)return result;
        if(!best||score<best.score)best={score,result};
        break;
      }
    }
    if(best)return best.result;
  }
  // Never silently truncate a new catalog title; browser checks flag this.
  const lines=wrap(title,80,6,measure)||[title];
  return {...centers[0],font:6,lineHeight:7.08,height:lines.length*7.08+(hasIcon?24:0),width:80,lines,rects:[],fits:false};
}
