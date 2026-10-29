#!/usr/bin/env node
// Check the browser port against the actual native geometry, without running
// either UI or changing user preferences. swiftc is optional off macOS.
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {SIZE,RADIUS,INNER,angle,petal,labelCenters,containsRect} from '../docs/assets/wheel-geometry.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const catalog=JSON.parse(readFileSync(join(root,'docs/assets/demo/catalog.json')));
assert.deepEqual(catalog.presentation.feedback,{voices:3,volume:.65,minimumInterval:.05});
assert.equal(SIZE,320);assert.equal(angle(3,0),180);
assert.equal(Object.keys(catalog.presentation.wheelTitles).length,27);
assert.equal(Object.keys(catalog.presentation.editorTitles).length,27);
for(const title of Object.values(catalog.presentation.wheelTitles))assert.ok(catalog.presentation.translations[title],`Missing native Turkish title: ${title}`);
assert.equal(catalog.presentation.palette.Paper.dark,'#111A14');
assert.deepEqual(readFileSync(join(root,'Resources/Sounds/WheelSelection.wav')),readFileSync(join(root,'docs/assets/demo/wheel-selection.wav')));
for(let count=1;count<=9;count++)for(let index=0;index<count;index++){
 assert.ok(!/NaN|Infinity/.test(petal(count,index)));
 assert.equal((petal(count,index).match(/ C/g)||[]).length,4,'Every petal keeps four rounded corners');
 const c=labelCenters(count,index)[0];assert.ok(Math.hypot(c.x-160,c.y-160)>INNER&&Math.hypot(c.x-160,c.y-160)<RADIUS);
}
assert.equal(containsRect({x:1,y:1,width:2,height:2},(x,y)=>x>=0&&y>=0&&x<=4&&y<=4,0),true);
assert.equal(containsRect({x:1,y:1,width:2,height:2},(x,y)=>x>=0&&y>=0&&x<=4&&y<=4),false,'Padding must protect labels from edges');
if(process.platform==='darwin'){
 const dir=mkdtempSync(join(tmpdir(),'nashi-web-geometry-'));
 try{
  const harness=join(dir,'main.swift'),binary=join(dir,'geometry');
  writeFileSync(harness,`import AppKit
var rows:[[String:Any]]=[]
for count in 1...9 { for index in 0..<count {
 let g=WheelGeometry(bounds:NSRect(x:0,y:0,width:320,height:320),count:count)
 let centers=g.labelCenters(index).map { [Double($0.x),Double(320-$0.y)] }
 var pts=[NSPoint](repeating:.zero,count:3)
 _=g.petal(index).element(at:0,associatedPoints:&pts)
 rows.append(["count":count,"index":index,"radius":Double(g.radius),"inner":Double(g.inner),"centers":centers,"move":[Double(pts[0].x),Double(320-pts[0].y)]])
}}
let data=try JSONSerialization.data(withJSONObject:rows)
print(String(data:data,encoding:.utf8)!)
`);
  const build=spawnSync('swiftc',[join(root,'Sources/NashiApp/WheelGeometry.swift'),harness,'-o',binary],{encoding:'utf8'});assert.equal(build.status,0,build.stderr);
  const run=spawnSync(binary,[],{encoding:'utf8'});assert.equal(run.status,0,run.stderr);
  const oracle=JSON.parse(run.stdout);
  for(const row of oracle){
   assert.ok(Math.abs(row.radius-RADIUS)<1e-9);assert.ok(Math.abs(row.inner-INNER)<1e-9);
   const centers=labelCenters(row.count,row.index);assert.equal(centers.length,row.centers.length);
   centers.forEach((c,i)=>{assert.ok(Math.abs(c.x-row.centers[i][0])<1e-8);assert.ok(Math.abs(c.y-row.centers[i][1])<1e-8);});
   const move=petal(row.count,row.index).match(/^M([\d.]+),([\d.]+)/);assert.ok(Math.abs(Number(move[1])-row.move[0])<.0001);assert.ok(Math.abs(Number(move[2])-row.move[1])<.0001);
  }
  console.log(`Native Swift/browser geometry agrees for ${oracle.length} petals and every label candidate.`);
 }finally{rmSync(dir,{recursive:true,force:true});}
}
console.log('Native catalog, Turkish labels, palette, rounded petals and sound asset checks passed.');
