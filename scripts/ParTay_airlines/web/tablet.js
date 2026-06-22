/* ============================================================
   tablet.js — pilot dispatch tablet
   Consumes the existing dispatch backend:
     Lua -> UI : businessTabletOpen {data}, businessTabletData {data}, businessTabletClose
     UI -> Lua : businessTabletClose, businessTabletRefresh,
                 businessTabletCreateFlight {routeId,aircraftModel,departureMinutes},
                 businessTabletClaimFlight {flightId},
                 businessTabletSetFlightStatus {flightId,status},
                 businessTabletCompleteFlight {flightId}
   ============================================================ */
(function () {
  if (!window.NUI) return;

  var root, contentEl, clockEl, toastEl, clockTimer = null;
  var state = { data: {}, tab: "flight", sched: { routeId: null, aircraftModel: null, minutes: 15 },
                last: null, session: { flights: 0, payout: 0 }, now: 0 };

  function $(id) { return document.getElementById(id); }
  function esc(s){ return String(s==null?"":s).replace(/[&<>]/g,function(c){return ({"&":"&amp;","<":"&lt;",">":"&gt;"})[c];}); }
  function money(n){ return "$" + (Math.round(+n||0)).toLocaleString(); }

  var STATUS = {
    scheduled:["Scheduled","amber"], awaiting_pilot:["Awaiting Pilot","amber"], boarding_soon:["Boarding Soon","amber"],
    boarding:["Boarding","amber"], final_call:["Final Call","amber"], boarding_closed:["Boarding Closed","cyan"],
    taxiing:["Taxiing","cyan"], taxi_hold:["Taxi Hold","cyan"], takeoff_hold:["Holding","cyan"],
    takeoff_cleared:["Cleared Takeoff","cyan"], in_air:["In Air","cyan"], approach:["Approach","cyan"],
    landed:["Landed","cyan"], deboarding:["Deboarding","green"], delayed:["Delayed","red"],
    completed:["Completed","green"], cancelled:["Cancelled","red"], failed:["Failed","red"]
  };
  function statusLabel(s){ return (STATUS[s]||[s||"-","amber"])[0]; }
  function statusClass(s){ return (STATUS[s]||["","amber"])[1]; }
  var AIRBORNE = {taxiing:1,taxi_hold:1,takeoff_hold:1,takeoff_cleared:1,in_air:1,approach:1,landed:1};

  function boot(){
    root = $("tablet-root"); if(!root) return;
    contentEl = $("t-content"); clockEl = $("t-clock"); toastEl = $("t-toast");
    root.querySelectorAll(".t-tab[data-tab]").forEach(function(b){
      b.addEventListener("click", function(){ state.tab = b.getAttribute("data-tab"); syncTabs(); render(); });
    });
    var x = $("t-close"); if(x) x.addEventListener("click", close);
    document.addEventListener("keydown", function(e){ if(e.key==="Escape" && root.classList.contains("t-on")) close(); });
  }

  function open(){ boot(); root.classList.add("t-on"); syncTabs(); render(); startClock(); }
  function close(){ if(!root) return; root.classList.remove("t-on"); stopClock(); NUI.post("businessTabletClose", {}); }

  function startClock(){
    stopClock();
    clockTimer = setInterval(function(){ state.now += 1; paintClock(); }, 1000); paintClock();
  }
  function stopClock(){ if(clockTimer){ clearInterval(clockTimer); clockTimer = null; } }
  function paintClock(){
    if(!clockEl) return;
    var d = new Date((state.now||Math.floor(Date.now()/1000))*1000);
    function p(n){ return String(n).padStart(2,"0"); }
    clockEl.textContent = p(d.getHours())+":"+p(d.getMinutes());
  }

  function setData(d){
    state.data = d || {};
    if(typeof state.data.now === "number") state.now = state.data.now;
    // header
    var b = $("t-airline"); if(b) b.textContent = (state.data.airline && state.data.airline.name) || "Airline Ops";
    var j = $("t-job");
    if(j){ var job = state.data.job||{}; j.textContent = (job.label||"Pilot") + (job.grade!=null?(" \u00b7 GRADE "+job.grade):""); }
    var duty = $("t-duty");
    if(duty){ var on = !state.data.job || state.data.job.onduty !== false;
      duty.textContent = on ? "On Duty" : "Off Duty"; duty.classList.toggle("off", !on); }
    paintClock(); render();
  }

  function syncTabs(){
    root.querySelectorAll(".t-tab").forEach(function(b){ b.classList.toggle("on", b.getAttribute("data-tab")===state.tab); });
    root.querySelectorAll(".t-pane").forEach(function(p){ p.classList.toggle("on", p.getAttribute("data-pane")===state.tab); });
  }

  function toast(msg, kind){
    if(!toastEl) return;
    toastEl.textContent = msg; toastEl.className = "t-toast show " + (kind||"");
    setTimeout(function(){ toastEl.classList.remove("show"); }, 2600);
  }

  function render(){
    if(!contentEl) return;
    syncTabs();
    var html = "";
    if(state.tab==="flight") html = renderFlight();
    else if(state.tab==="schedule") html = renderSchedule();
    else if(state.tab==="claim") html = renderClaim();
    else if(state.tab==="pax") html = renderPax();
    else if(state.tab==="earnings") html = renderEarnings();
    contentEl.innerHTML = html;
    wireButtons();
  }

  /* ---------------- MY FLIGHT ---------------- */
  function flightActions(f){
    var s = f.status, perms = state.data.permissions||{}, out = [];
    if(s==="scheduled"||s==="awaiting_pilot"||s==="boarding_soon") out.push(["Open Boarding","status","boarding","green"]);
    if(s==="boarding"){ out.push(["Final Call","status","final_call","amber"]); out.push(["Close Boarding","status","boarding_closed",""]); }
    if(s==="final_call") out.push(["Close Boarding","status","boarding_closed",""]);
    if(s==="boarding_closed") out.push(["Start Taxi","status","taxiing","cyan"]);
    if(s==="deboarding") out.push(["Complete Flight","complete","","green"]);
    if(s!=="completed"&&s!=="cancelled"&&s!=="failed") out.push(["Delay","status","delayed","amber"]);
    if((s!=="completed"&&s!=="cancelled"&&s!=="failed") && perms.cancelFlight!==false) out.push(["Cancel Flight","status","cancelled","red"]);
    return out;
  }
  function flightCard(f, withActions){
    var pct = f.seats>0 ? Math.round(f.boarded/f.seats*100) : 0;
    var tpct = f.seats>0 ? Math.round(f.ticketed/f.seats*100) : 0;
    var acts = withActions ? flightActions(f) : [];
    var btns = acts.map(function(a,i){
      return '<button class="t-btn '+a[3]+'" data-fa="'+i+'">'+a[0]+'</button>'; }).join("");
    var hint = AIRBORNE[f.status] ? '<div class="t-sub" style="margin-top:1.4cqh">Use the aircraft radio (Z) for taxi, runway &amp; takeoff clearances.</div>' : '';
    window.__faList = acts;
    return '<div class="t-card glow">'+
      '<div class="t-row"><div><div class="t-fn">'+esc(f.flightNumber)+'</div>'+
        '<div class="t-sub">'+esc(f.routeLabel||"")+'</div></div>'+
        '<span class="t-pill '+statusClass(f.status)+'">'+statusLabel(f.status)+'</span></div>'+
      '<div class="t-route"><div class="ap"><b>'+esc(f.departure||"--")+'</b><span>Origin</span></div>'+
        '<div class="ln"></div><div class="ap"><b>'+esc(f.arrival||"--")+'</b><span>Dest</span></div></div>'+
      '<div class="t-grid">'+
        '<div class="t-kv"><div class="k">Gate</div><div class="v cyan">'+esc(f.gate||"--")+'</div></div>'+
        '<div class="t-kv"><div class="k">Aircraft</div><div class="v">'+esc(f.aircraftLabel||"--")+'</div></div>'+
        '<div class="t-kv"><div class="k">Boarded</div><div class="v green">'+f.boarded+' / '+f.seats+'</div></div>'+
        '<div class="t-kv"><div class="k">Ticketed</div><div class="v amber">'+f.ticketed+' / '+f.seats+'</div></div>'+
      '</div>'+
      '<div class="t-kv"><div class="k">Boarding</div><div class="t-bar"><i style="width:'+Math.min(pct,100)+'%"></i></div></div>'+
      (btns ? '<div class="t-actions">'+btns+'</div>' : '')+ hint +
    '</div>';
  }
  function renderFlight(){
    var f = state.data.currentFlight;
    if(!f) return emptyState("plane","No active flight","Schedule a flight or claim one to get started.");
    return '<h3 class="t-h">My Flight</h3>' + flightCard(f, true);
  }

  /* ---------------- SCHEDULE ---------------- */
  function renderSchedule(){
    var perms = state.data.permissions||{};
    if(perms.createFlight===false) return emptyState("lock","Not cleared","Your grade can't schedule flights.");
    var routes = state.data.routes||[], aircraft = state.data.aircraft||[];
    if(!routes.length) return emptyState("calendar","No routes","No routes are configured.");
    var html = '<h3 class="t-h">Schedule Flight</h3><div class="t-list">';
    routes.forEach(function(r){
      var selected = state.sched.routeId===r.id;
      html += '<div class="t-item '+(selected?"sel":"")+'" data-route="'+esc(r.id)+'">'+
        '<div class="t-row"><div class="ttl">'+esc(r.label||r.id)+'</div><span class="t-pill cyan">'+esc(r.routeType||"domestic")+'</span></div>'+
        '<div class="meta">'+esc(r.departure||"")+' \u2192 '+esc(r.arrival||"")+' \u00b7 Gate '+esc(r.gate||"--")+' \u00b7 '+money(r.basePrice||0)+' base</div>';
      if(selected){
        html += '<div class="t-sub-options">';
        var list = r.allowedAircraft||[];
        if(!list.length) html += '<div class="t-sub">No aircraft allowed on this route.</div>';
        list.forEach(function(m){
          var ac = aircraft.filter(function(a){return a.model===m;})[0];
          var asel = state.sched.aircraftModel===m;
          html += '<div class="t-item '+(asel?"sel":"")+'" data-ac="'+esc(m)+'" data-route="'+esc(r.id)+'">'+
            '<div class="t-row"><div class="ttl">'+esc(ac?ac.label:m)+'</div><span class="t-sub">'+(ac?ac.seats:"?")+' seats</span></div></div>';
        });
        if(state.sched.aircraftModel){
          html += '<div class="t-stepper"><button data-step="-5">\u2212</button>'+
            '<span class="val" id="t-min">'+state.sched.minutes+'</span><span class="unit">min to departure</span>'+
            '<button data-step="5">+</button></div>'+
            '<div class="t-actions"><button class="t-btn green" id="t-do-schedule">Schedule Flight</button></div>';
        }
        html += '</div>';
      }
      html += '</div>';
    });
    html += '</div>';
    return html;
  }

  /* ---------------- CLAIM ---------------- */
  function renderClaim(){
    var perms = state.data.permissions||{};
    if(perms.claimFlight===false) return emptyState("lock","Not cleared","Your grade can't claim flights.");
    var flights = (state.data.flights||[]).filter(function(f){
      return !f.pilotAssigned && f.status!=="cancelled" && f.status!=="completed"; });
    if(!flights.length) return emptyState("plane","No unclaimed flights","Schedule one, or wait for dispatch to create flights.");
    var html = '<h3 class="t-h">Claim Flight</h3><div class="t-list">';
    flights.forEach(function(f){
      html += '<div class="t-item"><div class="t-row"><div class="ttl">'+esc(f.flightNumber)+'</div>'+
        '<span class="t-pill '+statusClass(f.status)+'">'+statusLabel(f.status)+'</span></div>'+
        '<div class="meta">'+esc(f.routeLabel||"")+' \u00b7 Gate '+esc(f.gate||"--")+' \u00b7 '+esc(f.aircraftLabel||"--")+' \u00b7 '+f.ticketed+' tickets</div>'+
        '<div class="t-actions"><button class="t-btn green" data-claim="'+f.id+'">Spawn &amp; Claim</button></div></div>';
    });
    html += '</div>';
    return html;
  }

  /* ---------------- PASSENGERS ---------------- */
  function renderPax(){
    var f = state.data.currentFlight;
    if(!f) return emptyState("users","No active flight","Claim or schedule a flight to see its manifest.");
    var seats = f.seats||0, boarded = f.boarded||0, ticketed = f.ticketed||0;
    var cells = "";
    for(var i=0;i<seats;i++){
      var cls = i<boarded ? "boarded" : (i<ticketed ? "ticketed" : "");
      cells += '<div class="t-seat '+cls+'"></div>';
    }
    var acts = flightActions(f).filter(function(a){ return a[2]==="boarding"||a[2]==="final_call"||a[2]==="boarding_closed"; });
    window.__faPax = acts;
    var btns = acts.map(function(a,i){ return '<button class="t-btn '+a[3]+'" data-fp="'+i+'">'+a[0]+'</button>'; }).join("");
    return '<h3 class="t-h">Passenger Manifest \u2014 '+esc(f.flightNumber)+'</h3>'+
      '<div class="t-card"><div class="t-grid">'+
        '<div class="t-kv"><div class="k">Boarded</div><div class="v green">'+boarded+'</div></div>'+
        '<div class="t-kv"><div class="k">Ticketed</div><div class="v amber">'+ticketed+'</div></div>'+
        '<div class="t-kv"><div class="k">Capacity</div><div class="v cyan">'+seats+'</div></div>'+
        '<div class="t-kv"><div class="k">Open Seats</div><div class="v">'+Math.max(seats-ticketed,0)+'</div></div>'+
      '</div>'+
      '<div class="t-seats">'+cells+'</div>'+
      '<div class="t-legend"><span><i style="background:#4be07c"></i>Boarded</span>'+
        '<span><i style="background:rgba(255,180,61,.6)"></i>Ticketed</span>'+
        '<span><i style="background:#0c1722;border:1px solid rgba(39,220,236,.32)"></i>Empty</span></div>'+
      (btns ? '<div class="t-actions">'+btns+'</div>' : '')+
    '</div>';
  }

  /* ---------------- EARNINGS ---------------- */
  function renderEarnings(){
    var f = state.data.currentFlight, html = '<h3 class="t-h">Earnings &amp; Stats</h3>';
    if(f){
      var route = (state.data.routes||[]).filter(function(r){return r.id===f.routeId;})[0] || {};
      var ac = (state.data.aircraft||[]).filter(function(a){return a.model===f.aircraftModel;})[0] || {};
      var gross = (route.basePrice||0) * (f.ticketed||0);
      var costs = (ac.fuelCost||0) + (ac.maintenanceCost||0);
      html += '<div class="t-card glow"><div class="t-sub">Current flight \u2014 '+esc(f.flightNumber)+' (projected)</div>'+
        '<div class="t-grid" style="margin-top:1.6cqh">'+
          '<div class="t-kv"><div class="k">Tickets sold</div><div class="v amber">'+(f.ticketed||0)+'</div></div>'+
          '<div class="t-kv"><div class="k">Base fare</div><div class="v">'+money(route.basePrice||0)+'</div></div>'+
          '<div class="t-kv"><div class="k">Gross</div><div class="v green">'+money(gross)+'</div></div>'+
          '<div class="t-kv"><div class="k">Est. costs</div><div class="v red">'+money(costs)+'</div></div>'+
        '</div>'+
        '<div class="t-kv" style="margin-top:1.4cqh"><div class="k">Projected net</div><div class="t-stat green">'+money(gross-costs)+'</div></div></div>';
    } else {
      html += '<div class="t-card"><div class="t-sub">No active flight \u2014 projections appear here once you claim one.</div></div>';
    }
    if(state.last){
      html += '<div class="t-card"><div class="t-sub">Last completed flight</div><div class="t-grid" style="margin-top:1.6cqh">'+
        '<div class="t-kv"><div class="k">Score</div><div class="v cyan">'+esc(state.last.score)+'%</div></div>'+
        '<div class="t-kv"><div class="k">Passengers</div><div class="v">'+esc(state.last.completedPassengers)+'</div></div>'+
        '<div class="t-kv"><div class="k">Pilot pay</div><div class="v green">'+money(state.last.pilotPayout)+'</div></div>'+
      '</div></div>';
    }
    html += '<div class="t-card"><div class="t-sub">This session</div><div class="t-grid" style="margin-top:1.6cqh">'+
      '<div class="t-kv"><div class="k">Flights completed</div><div class="v cyan">'+state.session.flights+'</div></div>'+
      '<div class="t-kv"><div class="k">Total pay</div><div class="v green">'+money(state.session.payout)+'</div></div>'+
    '</div></div>';
    return html;
  }

  function emptyState(icon,title,sub){
    return '<div class="t-empty">'+ICON[icon||"plane"]+'<div style="color:#cfe6ec;font-size:2.8cqh;margin-bottom:.6cqh">'+esc(title)+'</div>'+esc(sub||"")+'</div>';
  }

  /* ---------------- actions wiring ---------------- */
  function wireButtons(){
    // My Flight action buttons
    contentEl.querySelectorAll("[data-fa]").forEach(function(b){
      b.addEventListener("click", function(){ doFlightAction((window.__faList||[])[+b.getAttribute("data-fa")]); });
    });
    contentEl.querySelectorAll("[data-fp]").forEach(function(b){
      b.addEventListener("click", function(){ doFlightAction((window.__faPax||[])[+b.getAttribute("data-fp")]); });
    });
    // schedule route/aircraft/step/confirm
    contentEl.querySelectorAll("[data-route]:not([data-ac])").forEach(function(b){
      b.addEventListener("click", function(){
        var id=b.getAttribute("data-route");
        state.sched.routeId = (state.sched.routeId===id?null:id); state.sched.aircraftModel=null; render();
      });
    });
    contentEl.querySelectorAll("[data-ac]").forEach(function(b){
      b.addEventListener("click", function(e){ e.stopPropagation();
        state.sched.aircraftModel = b.getAttribute("data-ac"); render(); });
    });
    contentEl.querySelectorAll("[data-step]").forEach(function(b){
      b.addEventListener("click", function(){
        state.sched.minutes = Math.max(1, Math.min(240, state.sched.minutes + (+b.getAttribute("data-step"))));
        var m=$("t-min"); if(m) m.textContent = state.sched.minutes;
      });
    });
    var sb = $("t-do-schedule");
    if(sb) sb.addEventListener("click", function(){
      NUI.post("businessTabletCreateFlight", { routeId: state.sched.routeId, aircraftModel: state.sched.aircraftModel, departureMinutes: state.sched.minutes })
        .then(function(res){ res=res||{}; toast(res.message||(res.success?"Flight scheduled.":"Failed."), res.success?"ok":"err");
          if(res.success){ state.sched.aircraftModel=null; state.tab="claim"; } });
    });
    // claim
    contentEl.querySelectorAll("[data-claim]").forEach(function(b){
      b.addEventListener("click", function(){
        b.disabled=true; toast("Spawning aircraft\u2026");
        NUI.post("businessTabletClaimFlight", { flightId: +b.getAttribute("data-claim") })
          .then(function(res){ res=res||{}; toast(res.message||(res.success?"Claimed.":"Failed."), res.success?"ok":"err");
            if(res.success) state.tab="flight"; else b.disabled=false; });
      });
    });
  }

  function doFlightAction(a){
    var f = state.data.currentFlight; if(!a||!f) return;
    if(a[1]==="complete"){
      NUI.post("businessTabletCompleteFlight", { flightId: f.id }).then(function(res){
        res=res||{};
        if(res.success && res.result){ state.last=res.result; state.session.flights++; state.session.payout += (+res.result.pilotPayout||0);
          toast("Flight complete \u00b7 "+money(res.result.pilotPayout), "ok"); }
        else toast(res.message||"Could not complete.", "err");
      });
    } else {
      NUI.post("businessTabletSetFlightStatus", { flightId: f.id, status: a[2] }).then(function(res){
        res=res||{}; toast(res.message||(res.success?statusLabel(a[2]):"Failed."), res.success?"ok":"err");
      });
    }
  }

  var ICON = {
    plane:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5z"/></svg>',
    calendar:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 9h18M8 3v4M16 3v4"/></svg>',
    lock:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>',
    users:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="9" cy="8" r="3"/><path d="M3 20a6 6 0 0 1 12 0M16 6a3 3 0 0 1 0 6M21 20a5 5 0 0 0-4-5"/></svg>'
  };

  NUI.onMessage(function(msg){
    switch(msg.action){
      case "businessTabletOpen": setData(msg.data); open(); break;
      case "businessTabletData": setData(msg.data); break;
      case "businessTabletClose": if(root){ root.classList.remove("t-on"); stopClock(); } break;
    }
  });

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot); else boot();
})();
