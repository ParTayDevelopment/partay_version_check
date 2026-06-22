/* ============================================================
   airhud.js — glass cockpit HUD (PFD + MFD nav map)
   Passive overlay driven by client/main.lua.

   Lua -> UI (SendNUIMessage):
     airhudShow  {}
     airhudHide  {}
     airhudData  { pitch, roll, hdg, kias, altMSL, altAGL, vsi,
                   x, y, blips:[{x,y,type,label}], waypoint:{x,y}|null, gs }
       hdg = compass heading (0=N, 90=E, 180=S, 270=W)
       x,y = world coords (metres);  blips/waypoint use the same frame
   ============================================================ */
(function () {
  if (!window.NUI) return;

  var root, pfdCanvas, mfdCanvas, pctx, mctx, raf = null, dpr = 1;
  var device, curPos = null, dragging = false, dragOff = {x:0,y:0};
  var tgt = { pitch:0, roll:0, hdg:0, kias:0, altMSL:0, altAGL:0, vsi:0, gs:0,
              x:0, y:0, blips:[], waypoint:null };
  var cur = { pitch:0, roll:0, hdg:0, kias:0, altMSL:0, vsi:0, gs:0 };

  function $(id){ return document.getElementById(id); }
  function lerp(a,b,t){ return a + (b-a)*t; }
  function angLerp(a,b,t){ var d=((b-a+540)%360)-180; return a + d*t; }
  function rad(d){ return d*Math.PI/180; }

  var booted = false;
  function boot(){
    if (booted) return;
    root = $("airhud-root"); if(!root) return;
    pfdCanvas = $("airhud-pfdCanvas"); mfdCanvas = $("airhud-mfdCanvas");
    if(!pfdCanvas || !mfdCanvas) return;
    pctx = pfdCanvas.getContext("2d"); mctx = mfdCanvas.getContext("2d");
    booted = true;
    device = root.querySelector(".airhud-device");
    wireEdit();
    sizeCanvases();
    window.addEventListener("resize", sizeCanvases);
  }

  function applyPos(pos){
    if(!device) return;
    if(pos && pos.left != null){
      device.style.left = pos.left + "%";
      device.style.top = pos.top + "%";
      device.style.right = "auto"; device.style.bottom = "auto";
      device.style.transformOrigin = "top left";
      device.style.transform = "scale(" + (pos.scale || 1) + ")";
      curPos = { left: pos.left, top: pos.top, scale: pos.scale || 1 };
    } else {
      device.style.left = ""; device.style.top = ""; device.style.right = ""; device.style.bottom = "";
      device.style.transform = ""; device.style.transformOrigin = "";
      curPos = null;
    }
  }
  function freezeHud(){
    if(curPos) return;
    var r = device.getBoundingClientRect();
    curPos = { left:+(r.left/window.innerWidth*100).toFixed(3),
               top:+(r.top/window.innerHeight*100).toFixed(3), scale:1 };
    applyPos(curPos);
  }
  function saveHud(){ if(curPos) NUI.post("airhudSavePos", curPos); }
  function showEditbar(on){ var b=$("ui-editbar"); if(b) b.style.display = on?"flex":"none"; }
  function wireEdit(){
    if(!device) return;
    device.addEventListener("mousedown", function(e){
      if(!root.classList.contains("airhud-edit")) return;
      if(e.target.closest(".airhud-btn")||e.target.closest(".airhud-editbar")) return;
      freezeHud(); dragging = true;
      var r = device.getBoundingClientRect();
      dragOff.x = e.clientX - r.left; dragOff.y = e.clientY - r.top;
      e.preventDefault();
    });
    document.addEventListener("mousemove", function(e){
      if(!dragging) return;
      device.style.left = (e.clientX-dragOff.x)+"px"; device.style.top=(e.clientY-dragOff.y)+"px";
      device.style.right="auto"; device.style.bottom="auto";
    });
    document.addEventListener("mouseup", function(){
      if(!dragging) return; dragging=false;
      var r=device.getBoundingClientRect();
      curPos.left=+(r.left/window.innerWidth*100).toFixed(3);
      curPos.top=+(r.top/window.innerHeight*100).toFixed(3);
      applyPos(curPos); saveHud();
    });
    var szm=$("airhud-szminus"), szp=$("airhud-szplus");
    function nudge(d){ freezeHud(); curPos.scale=Math.max(0.5,Math.min(1.6,(curPos.scale||1)+d)); applyPos(curPos); saveHud(); }
    if(szm) szm.addEventListener("click",function(){ nudge(-0.1); });
    if(szp) szp.addEventListener("click",function(){ nudge(0.1); });
    var lock=$("ui-lock"), reset=$("ui-reset");
    if(lock) lock.addEventListener("click", function(){ NUI.post("uiEditExit", {}); });
    if(reset) reset.addEventListener("click", function(){ NUI.post("uiEditReset", {}); });
  }

  function sizeCanvases(){
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    [pfdCanvas, mfdCanvas].forEach(function(c){
      var r = c.getBoundingClientRect();
      c.width = Math.max(2, Math.round(r.width * dpr));
      c.height = Math.max(2, Math.round(r.height * dpr));
    });
  }

  function loop(){
    var t = 0.22;
    cur.pitch = lerp(cur.pitch, tgt.pitch, t);
    cur.roll  = lerp(cur.roll,  tgt.roll,  t);
    cur.hdg   = (angLerp(cur.hdg, tgt.hdg, t) + 360) % 360;
    cur.kias  = lerp(cur.kias,  tgt.kias,  t);
    cur.altMSL= lerp(cur.altMSL,tgt.altMSL,t);
    cur.vsi   = lerp(cur.vsi,   tgt.vsi,   t);
    cur.gs    = lerp(cur.gs,    tgt.gs,    t);
    drawPFD(); drawMFD();
    raf = requestAnimationFrame(loop);
  }

  /* ===================== PFD ===================== */
  function drawPFD(){
    var ctx = pctx, W = pfdCanvas.width, H = pfdCanvas.height;
    ctx.clearRect(0,0,W,H);
    var tapeL = W*0.15, tapeR = W*0.15, vsiW = W*0.05;
    var attL = tapeL, attR = W - tapeR - vsiW;
    var attTop = 0, attBot = H*0.87, attCx = (attL+attR)/2, attCy = attBot/2;
    var pxDeg = attBot/52;

    // ---- attitude ----
    ctx.save();
    ctx.beginPath(); ctx.rect(attL, attTop, attR-attL, attBot); ctx.clip();
    ctx.translate(attCx, attCy);
    ctx.rotate(rad(-cur.roll));
    var po = cur.pitch * pxDeg;
    var big = Math.max(W,H)*2.2;
    // sky
    ctx.fillStyle = "#2f86d8";
    ctx.fillRect(-big, -big, big*2, big + po);
    // ground
    ctx.fillStyle = "#7a5326";
    ctx.fillRect(-big, po, big*2, big);
    // horizon
    ctx.strokeStyle = "#ffffff"; ctx.lineWidth = Math.max(1.5, H*0.004);
    ctx.beginPath(); ctx.moveTo(-big, po); ctx.lineTo(big, po); ctx.stroke();
    // pitch ladder
    ctx.lineWidth = Math.max(1, H*0.0028); ctx.font = (H*0.028)+"px 'JetBrains Mono',monospace";
    ctx.fillStyle = "#fff"; ctx.textAlign="center"; ctx.textBaseline="middle";
    for (var a=-80; a<=80; a+=5){
      if (a===0) continue;
      var y = po - a*pxDeg;
      if (y < -attBot || y > attBot) continue;
      var major = (a%10===0);
      var halfW = major ? W*0.075 : W*0.04;
      ctx.strokeStyle = "#fff";
      ctx.beginPath(); ctx.moveTo(-halfW, y); ctx.lineTo(halfW, y); ctx.stroke();
      if (major){
        ctx.fillText(Math.abs(a), -halfW - W*0.03, y);
        ctx.fillText(Math.abs(a),  halfW + W*0.03, y);
      }
    }
    ctx.restore();

    // ---- bank arc + pointer ----
    ctx.save();
    ctx.translate(attCx, attCy);
    var arcR = attBot*0.46;
    ctx.strokeStyle="#fff"; ctx.lineWidth=Math.max(1,H*0.003);
    var marks=[-60,-45,-30,-20,-10,0,10,20,30,45,60];
    marks.forEach(function(m){
      var ang = rad(-90 + m);
      var r1 = arcR, r2 = arcR - (m%30===0?H*0.03:H*0.018);
      ctx.beginPath();
      ctx.moveTo(Math.cos(ang)*r1, Math.sin(ang)*r1);
      ctx.lineTo(Math.cos(ang)*r2, Math.sin(ang)*r2);
      ctx.stroke();
    });
    // roll pointer
    ctx.rotate(rad(-cur.roll));
    ctx.fillStyle="#ffd23a";
    ctx.beginPath();
    ctx.moveTo(0,-arcR);
    ctx.lineTo(-H*0.018,-arcR+H*0.03);
    ctx.lineTo(H*0.018,-arcR+H*0.03);
    ctx.closePath(); ctx.fill();
    ctx.restore();

    // ---- fixed aircraft reference ----
    ctx.strokeStyle="#ffd23a"; ctx.lineWidth=Math.max(2,H*0.006);
    ctx.beginPath();
    ctx.moveTo(attCx-W*0.10, attCy); ctx.lineTo(attCx-W*0.035, attCy);
    ctx.moveTo(attCx-W*0.035, attCy); ctx.lineTo(attCx-W*0.035, attCy+H*0.018);
    ctx.moveTo(attCx+W*0.10, attCy); ctx.lineTo(attCx+W*0.035, attCy);
    ctx.moveTo(attCx+W*0.035, attCy); ctx.lineTo(attCx+W*0.035, attCy+H*0.018);
    ctx.stroke();
    ctx.fillStyle="#ffd23a"; ctx.beginPath();
    ctx.arc(attCx, attCy, Math.max(2,H*0.006), 0, 7); ctx.fill();

    // ---- speed tape ----
    drawTape(ctx, 0, 0, tapeL, attBot, cur.kias, 10, 80, "#0d1620", "kt", false);
    // ---- altitude tape ----
    drawTape(ctx, attR, 0, tapeR, attBot, cur.altMSL, 100, 800, "#0d1620", "ft", true);
    // ---- VSI ----
    drawVSI(ctx, attR+tapeR, 0, vsiW, attBot, cur.vsi);
    // ---- heading strip ----
    drawHeading(ctx, 0, attBot, W, H-attBot, cur.hdg);
  }

  function drawTape(ctx, x, y, w, h, val, step, range, bg, unit, right){
    ctx.save();
    ctx.fillStyle="rgba(8,14,20,.72)"; ctx.fillRect(x,y,w,h);
    ctx.beginPath(); ctx.rect(x,y,w,h); ctx.clip();
    var cy=y+h/2, pxUnit=h/range;
    ctx.strokeStyle="#9fb3c0"; ctx.fillStyle="#cfe0ea";
    ctx.font=(h*0.035)+"px 'JetBrains Mono',monospace";
    ctx.textBaseline="middle"; ctx.lineWidth=1;
    var start=Math.floor((val-range/2)/step)*step;
    for(var v=start; v<=val+range/2; v+=step){
      if(v<0) continue;
      var ty=cy-(v-val)*pxUnit;
      var major=(v % (step*2)===0);
      ctx.beginPath();
      if(right){ ctx.moveTo(x,ty); ctx.lineTo(x+w*0.22,ty); } else { ctx.moveTo(x+w*0.78,ty); ctx.lineTo(x+w,ty); }
      ctx.stroke();
      if(major){ ctx.textAlign= right?"left":"right";
        ctx.fillText(v, right? x+w*0.28 : x+w*0.74, ty); }
    }
    // current value box
    ctx.fillStyle="#000"; ctx.strokeStyle="#fff"; ctx.lineWidth=Math.max(1.5,h*0.004);
    var bh=h*0.085, bw=w*0.96, bx=x+(w-bw)/2, by=cy-bh/2;
    ctx.fillRect(bx,by,bw,bh); ctx.strokeRect(bx,by,bw,bh);
    ctx.fillStyle="#fff"; ctx.font="bold "+(h*0.055)+"px 'JetBrains Mono',monospace";
    ctx.textAlign="center"; ctx.fillText(Math.round(val), x+w/2, cy);
    ctx.restore();
    ctx.fillStyle="#8fa3b0"; ctx.font=(h*0.03)+"px 'Saira Condensed',sans-serif";
    ctx.textAlign="center"; ctx.fillText(unit, x+w/2, y+h-h*0.02);
  }

  function drawVSI(ctx, x, y, w, h, vsi){
    ctx.save();
    ctx.fillStyle="rgba(8,14,20,.72)"; ctx.fillRect(x,y,w,h);
    var cy=y+h/2, maxF=2000, pxF=(h/2)/maxF;
    ctx.strokeStyle="#5b727e"; ctx.lineWidth=1;
    [-2000,-1000,0,1000,2000].forEach(function(f){
      var ty=cy-f*pxF; ctx.beginPath(); ctx.moveTo(x,ty); ctx.lineTo(x+w*0.4,ty); ctx.stroke();
    });
    var v=Math.max(-maxF,Math.min(maxF,vsi));
    ctx.fillStyle = vsi>=0 ? "#4be07c" : "#ff8a5b";
    var vy=cy - v*pxF;
    ctx.fillRect(x+w*0.45, Math.min(cy,vy), w*0.45, Math.abs(vy-cy));
    ctx.fillStyle="#cfe0ea"; ctx.font=(h*0.03)+"px 'JetBrains Mono',monospace";
    ctx.textAlign="center"; ctx.textBaseline="bottom";
    ctx.fillText(Math.round(vsi/10)*10, x+w/2, y+h-2);
    ctx.restore();
  }

  function drawHeading(ctx, x, y, w, h, hdg){
    ctx.save();
    ctx.fillStyle="rgba(8,14,20,.85)"; ctx.fillRect(x,y,w,h);
    ctx.beginPath(); ctx.rect(x,y,w,h); ctx.clip();
    var cx=x+w/2, pxDeg=w/70;
    ctx.strokeStyle="#9fb3c0"; ctx.fillStyle="#cfe0ea";
    ctx.font=(h*0.34)+"px 'JetBrains Mono',monospace"; ctx.textAlign="center"; ctx.textBaseline="top";
    var start=Math.round(hdg-35), end=Math.round(hdg+35);
    for(var d=start; d<=end; d++){
      if(((d%5)+5)%5!==0) continue;
      var dd=((d%360)+360)%360;
      var tx=cx+(d-hdg)*pxDeg;
      var major=(dd%10===0);
      ctx.beginPath(); ctx.moveTo(tx,y); ctx.lineTo(tx,y+(major?h*0.3:h*0.18)); ctx.stroke();
      if(dd%30===0){
        var lab = dd===0?"N":dd===90?"E":dd===180?"S":dd===270?"W":(dd/10);
        ctx.fillText(lab, tx, y+h*0.34);
      }
    }
    // current heading box
    ctx.fillStyle="#000"; ctx.strokeStyle="#fff"; ctx.lineWidth=Math.max(1.5,h*0.03);
    var bw=w*0.16, bh=h*0.6, bx=cx-bw/2, by=y+2;
    ctx.fillRect(bx,by,bw,bh); ctx.strokeRect(bx,by,bw,bh);
    ctx.fillStyle="#fff"; ctx.font="bold "+(h*0.44)+"px 'JetBrains Mono',monospace";
    ctx.textBaseline="middle"; ctx.fillText(("00"+Math.round(((hdg%360)+360)%360)).slice(-3), cx, by+bh/2);
    ctx.restore();
  }

  /* ===================== MFD nav map ===================== */
  function drawMFD(){
    var ctx=mctx, W=mfdCanvas.width, H=mfdCanvas.height;
    ctx.clearRect(0,0,W,H);
    ctx.fillStyle="#02060c"; ctx.fillRect(0,0,W,H);
    var cx=W/2, cy=H*0.60, hdg=cur.hdg;

    // pick a stable range from a ladder that fits the farthest blip
    var maxD=0, i, b, all=tgt.blips.slice();
    if(tgt.waypoint) all.push(tgt.waypoint);
    for(i=0;i<all.length;i++){ var dx=all[i].x-tgt.x, dy=all[i].y-tgt.y; maxD=Math.max(maxD, Math.hypot(dx,dy)); }
    var ladder=[1,2,5,10,20,40,80], rngNM=10;
    for(i=0;i<ladder.length;i++){ if(ladder[i]*1852 >= maxD*1.08){ rngNM=ladder[i]; break; } if(i===ladder.length-1) rngNM=ladder[i]; }
    var outR=Math.min(W,H)*0.42, scale=outR/(rngNM*1852);

    // range rings
    ctx.strokeStyle="rgba(90,140,160,.45)"; ctx.fillStyle="#5b8aa0";
    ctx.lineWidth=1; ctx.font=(H*0.03)+"px 'JetBrains Mono',monospace"; ctx.textAlign="left";
    [outR, outR*0.5].forEach(function(r,idx){
      ctx.beginPath(); ctx.arc(cx,cy,r,0,7); ctx.stroke();
      var nm = idx===0?rngNM:rngNM/2;
      ctx.fillText(nm+"nm", cx+2, cy-r-2);
    });

    // north pointer (track-up)
    ctx.save(); ctx.translate(cx,cy); ctx.rotate(rad(-hdg));
    ctx.strokeStyle="#8fb0c0"; ctx.fillStyle="#8fb0c0"; ctx.lineWidth=1.5;
    ctx.beginPath(); ctx.moveTo(0,-outR); ctx.lineTo(0,-outR+H*0.05); ctx.stroke();
    ctx.font="bold "+(H*0.04)+"px 'Saira Condensed',sans-serif"; ctx.textAlign="center";
    ctx.fillText("N", 0, -outR-H*0.01);
    ctx.restore();

    // blips
    function place(wx,wy){
      var ex=wx-tgt.x, ny=wy-tgt.y, dist=Math.hypot(ex,ny);
      var absB=Math.atan2(ex,ny);            // 0 = north, +→east
      var rel=absB - rad(hdg);               // track-up
      return { sx: cx + dist*scale*Math.sin(rel), sy: cy - dist*scale*Math.cos(rel), dist:dist };
    }
    // waypoint line + symbol (magenta)
    if(tgt.waypoint){
      var wp=place(tgt.waypoint.x, tgt.waypoint.y);
      ctx.strokeStyle="#ff4fd8"; ctx.lineWidth=Math.max(1.5,H*0.004);
      ctx.beginPath(); ctx.moveTo(cx,cy); ctx.lineTo(wp.sx,wp.sy); ctx.stroke();
      diamond(ctx, wp.sx, wp.sy, H*0.022, "#ff4fd8");
    }
    ctx.font=(H*0.032)+"px 'Saira Condensed',sans-serif"; ctx.textBaseline="middle"; ctx.textAlign="left";
    for(i=0;i<tgt.blips.length;i++){
      b=tgt.blips[i]; var p=place(b.x,b.y);
      if(Math.hypot(p.sx-cx,p.sy-cy) > outR*1.04) continue;
      var col = b.type==="dest" ? "#ff4fd8" : (b.type==="origin" ? "#4be07c" : "#37c0e0");
      if(b.type==="dest"||b.type==="origin"){ diamond(ctx,p.sx,p.sy,H*0.02,col); }
      else { ctx.fillStyle=col; ctx.fillRect(p.sx-H*0.012,p.sy-H*0.012,H*0.024,H*0.024); }
      if(b.label){ ctx.fillStyle=col; ctx.fillText(b.label, p.sx+H*0.02, p.sy); }
    }

    // ownship (yellow)
    ctx.save(); ctx.translate(cx,cy);
    ctx.fillStyle="#ffd23a";
    ctx.beginPath();
    ctx.moveTo(0,-H*0.045); ctx.lineTo(H*0.03,H*0.03); ctx.lineTo(0,H*0.012); ctx.lineTo(-H*0.03,H*0.03);
    ctx.closePath(); ctx.fill();
    ctx.restore();

    // readouts
    ctx.fillStyle="#9fe6ff"; ctx.font="bold "+(H*0.04)+"px 'Saira Condensed',sans-serif";
    ctx.textAlign="left"; ctx.textBaseline="top";
    ctx.fillText("TRK "+("00"+Math.round(hdg)).slice(-3)+"\u00b0", W*0.04, H*0.04);
    ctx.fillText("GS "+Math.round(cur.gs)+"kt", W*0.04, H*0.09);
    ctx.textAlign="right";
    ctx.fillText(rngNM+" NM", W*0.96, H*0.04);
    ctx.fillStyle="#5b727e"; ctx.fillText("MAP \u00b7 TRK UP", W*0.96, H*0.09);
  }
  function diamond(ctx,x,y,r,col){
    ctx.fillStyle=col; ctx.beginPath();
    ctx.moveTo(x,y-r); ctx.lineTo(x+r,y); ctx.lineTo(x,y+r); ctx.lineTo(x-r,y); ctx.closePath(); ctx.fill();
  }

  /* ===================== show / data ===================== */
  function show(){ boot(); if(!root) return; root.classList.add("airhud-on"); sizeCanvases(); if(!raf) raf=requestAnimationFrame(loop); }
  function hide(){ if(!root) return; root.classList.remove("airhud-on"); if(raf){ cancelAnimationFrame(raf); raf=null; } }

  NUI.onMessage(function(msg){
    switch(msg.action){
      case "airhudShow": show(); if(msg.pos) applyPos(msg.pos); break;
      case "airhudHide": hide(); break;
      case "airhudEdit":
        boot();
        if(msg.on){
          if(msg.reset) applyPos(null);
          else if(msg.pos) applyPos(msg.pos);
          root.classList.add("airhud-edit"); freezeHud(); showEditbar(true);
        } else { root.classList.remove("airhud-edit"); dragging=false; showEditbar(false); }
        break;
      case "airhudData":
        tgt.pitch=msg.pitch||0; tgt.roll=msg.roll||0; tgt.hdg=((msg.hdg||0)%360+360)%360;
        tgt.kias=msg.kias||0; tgt.altMSL=msg.altMSL||0; tgt.altAGL=msg.altAGL||0;
        tgt.vsi=msg.vsi||0; tgt.gs=msg.gs!=null?msg.gs:tgt.kias;
        tgt.x=msg.x||0; tgt.y=msg.y||0;
        tgt.blips=msg.blips||[]; tgt.waypoint=msg.waypoint||null;
        break;
    }
  });

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
