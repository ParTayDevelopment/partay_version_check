/* ============================================================
   atc.js — aircraft radio panel logic (pilot-facing ATC NUI)
   Talks to client/main.lua via the shared window.NUI bridge.

   Lua -> UI (SendNUIMessage):
     atcOpen      { facility, frequency, mode, status, onGround, emergency,
                    clearance:{text,emergency}, flight:{...} }
     atcClose     {}
     atcLog       { who, kind:'pilot'|'atc'|'sys', text }
     atcClearance { text, emergency }
     atcFlight    { ...flight fields }       (refresh Flight view)
     atcStatus    { connected, emergency }

   UI -> Lua (NUI.post / RegisterNUICallback):
     atcIntent    { intent }   intent = departure|takeoff|landing|transit|
                               emergency|touch_go|low_pass|flight_following
     atcReadback  {}
     atcClose     {}
   ============================================================ */
(function () {
  if (!window.NUI) return;

  var root, log, clearanceEl, clearanceWrap, readbackEl, freqEl, facEl, modeEl, statusEl;
  var lamp, statlamp, tx, vAtc, vFlight, extra, MAX = 60;
  var device, place = null, dragging = false, dragOff = {x:0,y:0};

  function $(id) { return document.getElementById(id); }

  function applyPlace(p){
    if(!device) return;
    if(p && p.left != null){
      device.style.left = p.left + "%"; device.style.top = p.top + "%";
      device.style.right = "auto"; device.style.bottom = "auto";
      device.style.transformOrigin = "top left";
      device.style.transform = "scale(" + (p.scale || 1) + ")";
      place = { left:p.left, top:p.top, scale:p.scale || 1 };
    } else {
      device.style.left=""; device.style.top=""; device.style.right=""; device.style.bottom="";
      device.style.transform=""; device.style.transformOrigin="";
      place = null;
    }
  }
  function freezeIfNeeded(){
    if(place) return;
    var r = device.getBoundingClientRect();
    place = { left:+(r.left/window.innerWidth*100).toFixed(3),
              top:+(r.top/window.innerHeight*100).toFixed(3), scale:1 };
    applyPlace(place);
  }
  function saveAtc(){ if(place) NUI.post("atcSavePos", place); }

  function boot() {
    root = $("atc-root");
    if (!root) return;
    log = $("atc-log");
    clearanceEl = $("atc-clearance");
    clearanceWrap = $("atc-clr");
    readbackEl = $("atc-readback");
    freqEl = $("atc-freq"); facEl = $("atc-fac"); modeEl = $("atc-mode"); statusEl = $("atc-status");
    lamp = $("atc-lamp"); statlamp = $("atc-statlamp"); tx = $("atc-tx");
    vAtc = $("atc-vAtc"); vFlight = $("atc-vFlight"); extra = $("atc-extra");

    // request buttons -> intents
    root.querySelectorAll(".atc-rbtn[data-intent]").forEach(function (b) {
      b.addEventListener("click", function () {
        flashTx();
        NUI.post("atcIntent", { intent: b.getAttribute("data-intent") });
      });
    });
    // more toggle
    var mt = $("atc-moretoggle");
    if (mt) mt.addEventListener("click", function () {
      extra.classList.toggle("atc-shown");
      mt.textContent = extra.classList.contains("atc-shown") ? "Less" : "More requests";
    });
    // XMIT -> readback
    var hx = $("atc-hotXmit");
    if (hx) hx.addEventListener("click", function () {
      hx.classList.remove("atc-flash"); void hx.offsetWidth; hx.classList.add("atc-flash");
      flashTx(); NUI.post("atcReadback", {});
    });
    // ATC hardware button -> toggle ATC <-> Flight
    var ha = $("atc-hotAtc");
    if (ha) ha.addEventListener("click", function () {
      ha.classList.remove("atc-flash"); void ha.offsetWidth; ha.classList.add("atc-flash");
      var showFlight = vAtc.classList.contains("atc-on");
      vAtc.classList.toggle("atc-on", !showFlight);
      vFlight.classList.toggle("atc-on", showFlight);
    });
    // ESC or Backspace closes
    document.addEventListener("keydown", function (e) {
      if ((e.key === "Escape" || e.key === "Backspace") && root.classList.contains("atc-open")) {
        e.preventDefault(); doClose();
      }
    });

    // ---- edit (move/resize) wiring ----
    device = root.querySelector(".atc-device");
    device.addEventListener("mousedown", function(e){
      if(!root.classList.contains("atc-editing")) return;
      if(e.target.closest(".atc-szbtn") || e.target.closest(".atc-editbar")) return;
      freezeIfNeeded(); dragging = true;
      var r = device.getBoundingClientRect();
      dragOff.x = e.clientX - r.left; dragOff.y = e.clientY - r.top;
      e.preventDefault();
    });
    document.addEventListener("mousemove", function(e){
      if(!dragging) return;
      device.style.left = (e.clientX - dragOff.x) + "px";
      device.style.top = (e.clientY - dragOff.y) + "px";
      device.style.right = "auto"; device.style.bottom = "auto";
    });
    document.addEventListener("mouseup", function(){
      if(!dragging) return; dragging = false;
      var r = device.getBoundingClientRect();
      place.left = +(r.left/window.innerWidth*100).toFixed(3);
      place.top = +(r.top/window.innerHeight*100).toFixed(3);
      applyPlace(place); saveAtc();
    });
    var szm = $("atc-szminus"), szp = $("atc-szplus");
    function nudge(d){ freezeIfNeeded(); place.scale = Math.max(0.5, Math.min(1.6, (place.scale||1)+d));
      applyPlace(place); saveAtc(); }
    if(szm) szm.addEventListener("click", function(){ nudge(-0.1); });
    if(szp) szp.addEventListener("click", function(){ nudge(0.1); });
  }

  function zstamp() {
    var d = new Date();
    function p(n){ return String(n).padStart(2, "0"); }
    return p(d.getUTCHours()) + ":" + p(d.getUTCMinutes()) + ":" + p(d.getUTCSeconds()) + "Z";
  }
  function flashTx() { if (!tx) return; tx.classList.add("atc-on"); setTimeout(function(){ tx.classList.remove("atc-on"); }, 750); }
  function blinkRx() { if (!lamp) return; lamp.classList.remove("atc-rx"); void lamp.offsetWidth; lamp.classList.add("atc-rx"); }

  function appendLog(kind, who, text) {
    if (!log) return;
    var empty = log.querySelector(".atc-logempty"); if (empty) empty.remove();
    var m = document.createElement("div");
    m.className = "atc-msg " + kind;
    if (kind === "sys") { m.textContent = text; }
    else { m.innerHTML = '<div class="meta">' + zstamp() + ' \u00b7 ' + (($("atc-freqNum") && $("atc-freqNum").textContent) || "") + '</div><span class="who">' + esc(who) + ':</span> ' + esc(text); }
    log.appendChild(m);
    while (log.children.length > MAX) log.removeChild(log.firstChild);
    log.scrollTop = log.scrollHeight;
  }
  function esc(s){ return String(s == null ? "" : s).replace(/[&<>]/g, function(c){ return ({"&":"&amp;","<":"&lt;",">":"&gt;"})[c]; }); }

  function setClearance(text, emergency, readbackRequired, readbackComplete) {
    if (clearanceEl) clearanceEl.textContent = text || "None";
    if (clearanceWrap) clearanceWrap.classList.toggle("atc-emc", !!emergency);
    if (readbackEl) {
      readbackEl.classList.toggle("need", !!readbackRequired && !readbackComplete);
      readbackEl.classList.toggle("done", !!readbackRequired && !!readbackComplete);
      readbackEl.textContent = readbackRequired
        ? (readbackComplete ? "Readback received" : "Awaiting pilot readback - press XMIT")
        : "No readback required";
    }
  }
  function setStatusLamp(emergency) {
    if (statlamp) statlamp.classList.toggle("atc-em", !!emergency);
  }

  function renderFlight(f) {
    f = f || {};
    set("atc-fCallsign", f.callsign || "----");
    set("atc-fAirline", f.airline || "");
    set("atc-fOrigin", f.origin || "----");
    set("atc-fDest", f.dest || "----");
    set("atc-fAircraft", f.aircraft || "Aircraft");
    set("atc-fGate", f.gate || "--");
    set("atc-fStatusPill", f.statusLabel || f.status || "Standby");
    var booked = f.booked != null ? f.booked : 0, seats = f.seats != null ? f.seats : 0, boarded = f.boarded != null ? f.boarded : 0;
    set("atc-fBooked", booked + " "); set("atc-fSeats1", "/ " + seats); set("atc-fSeats2", "/ " + seats);
    set("atc-fBoarded", boarded + " ");
    var bw = seats > 0 ? Math.round(booked / seats * 100) : 0;
    var rw = seats > 0 ? Math.round(boarded / seats * 100) : 0;
    var b1 = $("atc-barBooked"), b2 = $("atc-barBoarded");
    if (b1) b1.style.width = Math.min(bw, 100) + "%";
    if (b2) b2.style.width = Math.min(rw, 100) + "%";
    // hide flight view entirely if no active flight
    var hasFlight = !!f.callsign;
    if (vFlight) vFlight.dataset.has = hasFlight ? "1" : "0";
  }
  function set(id, v){ var el = $(id); if (el) el.textContent = v; }

  function doOpen(msg) {
    set("atc-freqNum", msg.frequency || "122.800");
    set("atc-fac", msg.facility || "ATC");
    set("atc-mode", msg.mode || "Flight");
    set("atc-status", msg.status || "Connected");
    if (msg.clearance) setClearance(msg.clearance.text, msg.clearance.emergency, msg.clearance.readbackRequired, msg.clearance.readbackComplete);
    setStatusLamp(msg.emergency);
    if (msg.flight) renderFlight(msg.flight);
    // default to ATC view
    vAtc.classList.add("atc-on"); vFlight.classList.remove("atc-on");
    if (msg.pos) applyPlace(msg.pos);
    root.classList.add("atc-open");
  }
  function doClose() {
    root.classList.remove("atc-open");
    if (extra) extra.classList.remove("atc-shown");
    NUI.post("atcClose", {});
  }

  NUI.onMessage(function (msg) {
    switch (msg.action) {
      case "atcOpen": doOpen(msg); break;
      case "atcClose": root.classList.remove("atc-open"); break;
      case "atcLog":
        appendLog(msg.kind || "atc", msg.who || "ATC", msg.text || "");
        if ((msg.kind || "atc") === "atc") blinkRx();
        break;
      case "atcClearance": setClearance(msg.text, msg.emergency, msg.readbackRequired, msg.readbackComplete); if (msg.emergency) setStatusLamp(true); break;
      case "atcFlight": renderFlight(msg); break;
      case "atcStatus": setStatusLamp(msg.emergency); break;
      case "atcEdit":
        boot();
        if (msg.on) {
          if (msg.reset) applyPlace(null);
          else if (msg.pos) applyPlace(msg.pos);
          root.classList.add("atc-open");      // show as preview
          root.classList.add("atc-editing");
          freezeIfNeeded();
        } else {
          root.classList.remove("atc-editing");
          dragging = false;
          if (!msg.keepOpen) root.classList.remove("atc-open");
        }
        break;
    }
  });

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
