/* ============================================================
   app.js — Airport Creator UI logic
   Talks to client/creator.lua ONLY through these callbacks:
     creatorClose, creatorSaveAirport, creatorPatchAirport,
     creatorSelection, creatorPlace, creatorTestAirport,
     creatorCurrentPoint
   and reacts to these SendNUIMessage actions:
     open, close, airports, pointPlaced, polyPlaced,
     zonePlaced, ghostPlaced
   No Lua behaviour is assumed beyond that contract.
   ============================================================ */
(function () {
  "use strict";

  var ZONE_KEYS = ["taxiHold", "takeoffHold", "takeoffZone", "approachZone", "landingZone", "arrivalGate"];
  var RUNWAY_ZONE_KEYS = ["taxiHold", "takeoffHold", "takeoffZone", "approachZone", "landingZone"];
  var ZONE_LABELS = {
    taxiHold: "Taxi hold", takeoffHold: "Takeoff hold", takeoffZone: "Takeoff zone",
    approachZone: "Approach zone", landingZone: "Landing zone", arrivalGate: "Arrival gate"
  };
  var ZONE_DESC = {
    taxiHold: "Hold short before entering the runway.",
    takeoffHold: "Lined-up-and-waiting hold on the runway.",
    takeoffZone: "Roll-out trigger that confirms departure.",
    approachZone: "Final approach gate the arrival must cross.",
    landingZone: "Touchdown box that completes the landing.",
    arrivalGate: "Arrival hand-off back to ground control."
  };

  var state = {
    airports: [],
    currentId: null,
    tab: "overview",
    runwayIndex: 0,
    status: "ready"
  };

  // ---------- tiny helpers ----------
  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function num(v, d) { var n = parseFloat(v); return isNaN(n) ? (d || 0) : n; }
  function vec(c) {
    c = c || {};
    return {
      x: num(c.x != null ? c.x : c[0]),
      y: num(c.y != null ? c.y : c[1]),
      z: num(c.z != null ? c.z : c[2]),
      w: num(c.w != null ? c.w : c[3])
    };
  }
  function getPath(obj, path) {
    var parts = path.split("."), o = obj;
    for (var i = 0; i < parts.length; i++) { if (o == null) return undefined; o = o[parts[i]]; }
    return o;
  }
  function setPath(obj, path, val) {
    var parts = path.split("."), o = obj;
    for (var i = 0; i < parts.length - 1; i++) {
      if (o[parts[i]] == null || typeof o[parts[i]] !== "object") o[parts[i]] = {};
      o = o[parts[i]];
    }
    o[parts[parts.length - 1]] = val;
  }

  function normalizeAirport(a) {
    a = a || {};
    a.runways = a.runways || [];
    a.gates = a.gates || [];
    a.hangars = a.hangars || [];
    a.zones = a.zones || {};
    a.atc = a.atc || {};
    a.atc.coords = vec(a.atc.coords);
    if (a.atc.coverageRadius == null) a.atc.coverageRadius = 1200;
    a.airspace = a.airspace || {};
    if (a.airspace.enabled == null) a.airspace.enabled = true;
    if (a.airspace.radius == null) a.airspace.radius = 2500;
    if (a.airspace.altitudeMin == null) a.airspace.altitudeMin = 0;
    if (a.airspace.altitudeMax == null) a.airspace.altitudeMax = 1600;
    a.blip = a.blip || {};
    if (a.blip.enabled == null) a.blip.enabled = true;
    if (a.blip.sprite == null) a.blip.sprite = 90;
    if (a.blip.color == null) a.blip.color = 3;
    if (a.blip.scale == null) a.blip.scale = 0.85;
    if (a.restricted == null) a.restricted = false;
    return a;
  }

  function current() {
    for (var i = 0; i < state.airports.length; i++)
      if (state.airports[i].id === state.currentId) return state.airports[i];
    return null;
  }

  function replaceAirport(ap) {
    ap = normalizeAirport(ap);
    var found = false;
    for (var i = 0; i < state.airports.length; i++) {
      if (state.airports[i].id === ap.id) { state.airports[i] = ap; found = true; break; }
    }
    if (!found) state.airports.push(ap);
    state.currentId = ap.id;
    return ap;
  }

  // ---------- status pill ----------
  function setStatus(s, text) {
    state.status = s;
    var pill = $("#statusPill");
    pill.setAttribute("data-state", s);
    var map = { ready: "Ready", unsaved: "Unsaved", saving: "Saving…", saved: "Saved", error: "Error" };
    $("#statusText").textContent = text || map[s] || "Ready";
  }
  function markUnsaved() { if (state.status !== "saving") setStatus("unsaved"); }

  // ---------- selection -> Lua (drives in-world preview) ----------
  function sendSelection() {
    NUI.post("creatorSelection", {
      airportId: state.currentId,
      airport: current(),
      tab: state.tab,
      runwayZoneIndex: state.runwayIndex,
      directionZoneIndex: -1
    });
  }

  // ---------- zone status helpers ----------
  function zoneOf(holder, key) { return (holder && (holder.zones && holder.zones[key])) || (holder && holder[key]) || null; }
  function zoneSummary(z) {
    if (!z) return null;
    if (Array.isArray(z)) return z.length + " zones";
    var t = (z.type || "sphere");
    if (t === "poly") return "POLY · " + ((z.points && z.points.length) || 0) + " pts";
    if (t === "box") return "BOX · " + Math.round(z.length || 0) + "×" + Math.round(z.width || 0);
    return "SPHERE · r" + Math.round(z.radius || 0);
  }
  function chip(setText) {
    if (setText) return '<span class="chip is-set"><span class="dot"></span>' + esc(setText) + "</span>";
    return '<span class="chip"><span class="dot"></span>Not set</span>';
  }

  function runwayPoints(r) {
    var zone = r && r.zone;
    var points = (zone && zone.points) || (r && r.points) || [];
    var out = [];
    for (var i = 0; i < points.length; i++) out.push(vec(points[i]));
    return out;
  }

  function pointAlong(origin, ux, uy, px, py, forward, side, z) {
    return {
      x: origin.x + (ux * forward) + (px * side),
      y: origin.y + (uy * forward) + (py * side),
      z: z == null ? origin.z : z
    };
  }

  function rectZone(label, origin, ux, uy, width, start, finish, minZ, maxZ, extra) {
    var px = -uy;
    var py = ux;
    var half = width * 0.5;
    var points = [
      pointAlong(origin, ux, uy, px, py, start, -half, minZ),
      pointAlong(origin, ux, uy, px, py, finish, -half, minZ),
      pointAlong(origin, ux, uy, px, py, finish, half, minZ),
      pointAlong(origin, ux, uy, px, py, start, half, minZ)
    ];
    var zone = { type: "poly", label: label, points: points, minZ: minZ, maxZ: maxZ, thickness: Math.max(10, maxZ - minZ) };
    if (extra) {
      for (var key in extra) {
        if (Object.prototype.hasOwnProperty.call(extra, key)) zone[key] = extra[key];
      }
    }
    return zone;
  }

  function autoBuildRunwayZones(r, runwayIndex) {
    var points = runwayPoints(r);
    if (points.length < 4) return false;

    var a = points[0], b = points[1], longest = 0;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        var dx = points[j].x - points[i].x;
        var dy = points[j].y - points[i].y;
        var dist = Math.sqrt((dx * dx) + (dy * dy));
        if (dist > longest) {
          longest = dist;
          a = points[i];
          b = points[j];
        }
      }
    }
    if (longest < 20) return false;

    var ux = (b.x - a.x) / longest;
    var uy = (b.y - a.y) / longest;
    var px = -uy;
    var py = ux;
    var minAlong = 0, maxAlong = longest, maxSide = 12, zTotal = 0;
    for (var p = 0; p < points.length; p++) {
      var rx = points[p].x - a.x;
      var ry = points[p].y - a.y;
      var along = (rx * ux) + (ry * uy);
      var side = Math.abs((rx * px) + (ry * py));
      minAlong = Math.min(minAlong, along);
      maxAlong = Math.max(maxAlong, along);
      maxSide = Math.max(maxSide, side);
      zTotal += points[p].z || a.z || 0;
    }

    var length = Math.max(80, maxAlong - minAlong);
    var width = Math.max(35, maxSide * 2.4);
    var groundZ = zTotal / points.length;
    var runwayStart = minAlong;
    var runwayEnd = maxAlong;
    var approachLength = Math.max(450, length * 1.25);
    var departureExtra = Math.max(250, length * 0.45);
    var landingLength = Math.min(Math.max(120, length * 0.38), length * 0.55);
    var lowZ = groundZ + 35;
    var highZ = groundZ + 160;

    function makeDirection(id, label, thresholdAlong, departureAlong, dirUx, dirUy) {
      var threshold = pointAlong(a, ux, uy, px, py, thresholdAlong, 0, groundZ);
      var departureEnd = pointAlong(a, ux, uy, px, py, departureAlong, 0, groundZ);
      var heading = (Math.atan2(dirUx, dirUy) * 180 / Math.PI + 360) % 360;
      var approach = rectZone(label + " Approach", threshold, dirUx, dirUy, width * 1.8, -approachLength, 0, lowZ, highZ, {
        glideSlope: {
          threshold: threshold,
          axis: { x: -dirUx, y: -dirUy },
          length: approachLength,
          thresholdAltitude: 35,
          outerAltitude: 160,
          tolerance: 70
        }
      });
      var landing = rectZone(label + " Landing", threshold, dirUx, dirUy, width * 1.25, 0, landingLength, groundZ - 8, groundZ + 75);
      var takeoff = rectZone(label + " Takeoff", threshold, dirUx, dirUy, width * 1.35, 0, length + departureExtra, lowZ, highZ);

      return {
        id: id,
        label: label,
        heading: heading,
        threshold: threshold,
        departureEnd: departureEnd,
        zones: { takeoffZone: takeoff, approachZone: approach, landingZone: landing }
      };
    }

    var label = r.label || ("Runway " + (runwayIndex + 1));
    var dirA = makeDirection("a", label + " A", runwayStart, runwayEnd, ux, uy);
    var dirB = makeDirection("b", label + " B", runwayEnd, runwayStart, -ux, -uy);

    r.directions = [dirA, dirB];
    r.zones = r.zones || {};
    r.zones.takeoffZone = [dirA.zones.takeoffZone, dirB.zones.takeoffZone];
    r.zones.approachZone = [dirA.zones.approachZone, dirB.zones.approachZone];
    r.zones.landingZone = [dirA.zones.landingZone, dirB.zones.landingZone];
    r.takeoffZone = r.zones.takeoffZone;
    r.approachZone = r.zones.approachZone;
    r.landingZone = r.zones.landingZone;

    return true;
  }

  // ============================================================
  //  TAB RENDERERS
  // ============================================================
  function head(eyebrow, title, desc) {
    return '<div class="page-head"><div class="eyebrow">' + esc(eyebrow) + "</div><h1>" +
      esc(title) + "</h1>" + (desc ? "<p>" + esc(desc) + "</p>" : "") + "</div>";
  }

  function renderOverview(a) {
    var runways = a.runways.length, gates = a.gates.length;
    var zonesSet = ZONE_KEYS.filter(function (k) { return zoneOf(a, k); }).length;
    var airState = a.airspace.enabled ? "Enabled" : "Disabled";
    return head("Station identity", a.label || a.id, "The basics every other tab builds on — call sign, station handle, and the operational flags.") +
      '<div class="card"><div class="card-head"><span class="label">Identity</span></div>' +
      '<div class="grid">' +
        field("Airport ID", a.id, null, { readonly: true, hint: "Set at creation — locked" }) +
        field("Display label", a.label || "", "label", { text: true }) +
        field("Tower call sign", a.tower || "", "tower", { text: true, col2: true }) +
      "</div></div>" +

      '<div class="card"><div class="card-head"><span class="label">Flags</span></div>' +
      '<div class="flex flex-wrap" style="gap:24px">' +
        toggle("International (customs)", a.international === true, "international") +
        toggle("Debug zones", a.debug === true, "debug") +
        toggle("Hidden from blip list", a.hidden === true, "hidden") +
      "</div></div>" +

      '<div class="card"><div class="card-head"><span class="label">Station summary</span></div>' +
      '<div class="flex flex-wrap" style="gap:10px">' +
        chip("Runways · " + runways) + chip("Gates · " + gates) +
        chip("Trigger zones · " + zonesSet + "/" + ZONE_KEYS.length) +
        (a.airspace.enabled ? chip("Airspace · " + airState) : '<span class="chip is-pending"><span class="dot"></span>Airspace · Disabled</span>') +
        (a.restricted ? '<span class="chip is-pending"><span class="dot"></span>Restricted</span>' : "") +
      "</div>" +
      (a.updatedAt ? '<div class="readout" style="margin-top:14px;margin-bottom:0">Last saved <b>' + esc(a.updatedAt) + "</b></div>" : "") +
      "</div>";
  }

  function renderATC(a) {
    var c = a.atc.coords;
    var poly = a.airspace.controlledZone;
    var readout =
      '<div class="readout">' +
      "Airport ID: <b>" + esc(a.id) + "</b><br>" +
      "ATC point: <b>" + c.x.toFixed(2) + " " + c.y.toFixed(2) + " " + c.z.toFixed(2) + "</b> / H " + c.w.toFixed(1) + "<br>" +
      'Airspace: <b>' + (a.airspace.enabled ? "enabled" : "disabled") + "</b> · radius " + Math.round(a.airspace.radius) +
      " · Z " + Math.round(a.airspace.altitudeMin) + "–" + Math.round(a.airspace.altitudeMax) +
      "</div>";

    return head("Tower / traffic control", "ATC & airspace", "Set the tower position, contact ranges, and the airspace that drives entry, hand-off and exit callouts.") +
      '<div class="card"><div class="card-head"><span class="label">Control point</span><span class="grow"></span>' +
        chip((c.x || c.y) ? "Set" : null) + "</div>" +
        readout + scopeBlock(a) +
        '<div class="grid">' +
          field("ATC X", c.x, "atc.coords.x", { number: true }) +
          field("ATC Y", c.y, "atc.coords.y", { number: true }) +
          field("ATC Z", c.z, "atc.coords.z", { number: true }) +
          field("Heading", c.w, "atc.coords.w", { number: true }) +
        "</div>" +
        '<div class="actions">' +
          '<button class="btn btn--amber" data-act="place-atc">Raycast ATC point</button>' +
          '<button class="btn" data-act="current-atc">Use current position</button>' +
        "</div></div>" +

      '<div class="card"><div class="card-head"><span class="label">Coverage & airspace</span></div>' +
        '<div class="grid">' +
          field("ATC coverage radius", a.atc.coverageRadius, "atc.coverageRadius", { number: true }) +
          selectField("Airport airspace", a.airspace.enabled ? "1" : "0", "airspace.enabled", [["1", "Enabled"], ["0", "Disabled"]], { bool: true }) +
          field("Airspace radius", a.airspace.radius, "airspace.radius", { number: true }) +
          field("Min altitude", a.airspace.altitudeMin, "airspace.altitudeMin", { number: true }) +
          field("Max altitude", a.airspace.altitudeMax, "airspace.altitudeMax", { number: true }) +
        "</div></div>" +

      '<div class="card"><div class="card-head"><span class="label">Future custom boundary</span><span class="grow"></span>' +
        chip(poly ? "Poly · " + ((poly.points && poly.points.length) || 0) + " pts" : null) + "</div>" +
        '<p class="muted" style="font-size:12px;margin:0 0 14px;line-height:1.5">The radius bubble is the active ATC boundary for entry, exit, and runway assignment timing. Custom polygons can be saved for later, but they are inactive right now.</p>' +
        '<div class="actions" style="margin-top:0">' +
          '<button class="btn btn--amber" data-act="place-airspace-poly">Draw airspace poly</button>' +
          (poly ? '<button class="btn btn--danger" data-act="delete-airspace-poly">Delete poly</button>' : "") +
        "</div></div>" +

      '<div class="card"><div class="card-head"><span class="label">Test in world</span></div>' +
        '<p class="muted" style="font-size:12px;margin:0 0 14px;line-height:1.5">Fly or drive through the live zones with an on-screen readout. Backspace exits back here.</p>' +
        '<div class="actions" style="margin-top:0"><button class="btn" data-act="test-airport">Start airport test</button></div>' +
      "</div>";
  }

  function scopeBlock(a) {
    var cov = num(a.atc.coverageRadius, 0);
    var air = a.airspace.enabled ? num(a.airspace.radius, 0) : 0;
    var maxR = Math.max(cov, air, 1);
    var R = 92; // px outer
    var covR = (cov / maxR) * R;
    var airR = (air / maxR) * R;
    var cx = 110, cy = 110;
    var rings = "";
    [0.25, 0.5, 0.75, 1].forEach(function (f) {
      rings += '<circle cx="' + cx + '" cy="' + cy + '" r="' + (R * f).toFixed(1) +
        '" fill="none" stroke="rgba(126,158,178,0.12)" stroke-width="1"/>';
    });
    var ticks = "";
    for (var d = 0; d < 360; d += 30) {
      var rad = (d - 90) * Math.PI / 180;
      var x1 = cx + Math.cos(rad) * (R - 6), y1 = cy + Math.sin(rad) * (R - 6);
      var x2 = cx + Math.cos(rad) * R, y2 = cy + Math.sin(rad) * R;
      ticks += '<line x1="' + x1.toFixed(1) + '" y1="' + y1.toFixed(1) + '" x2="' + x2.toFixed(1) +
        '" y2="' + y2.toFixed(1) + '" stroke="rgba(126,158,178,0.25)" stroke-width="1"/>';
    }
    var svg =
      '<svg width="220" height="220" viewBox="0 0 220 220" aria-hidden="true">' +
      '<defs><radialGradient id="sweep" cx="50%" cy="50%" r="50%">' +
        '<stop offset="0%" stop-color="rgba(52,210,122,0.28)"/><stop offset="100%" stop-color="rgba(52,210,122,0)"/>' +
      "</radialGradient></defs>" +
      rings + ticks +
      (air > 0 ? '<circle cx="' + cx + '" cy="' + cy + '" r="' + airR.toFixed(1) + '" fill="rgba(244,177,58,0.05)" stroke="#f4b13a" stroke-width="1.4" stroke-dasharray="4 4"/>' : "") +
      (cov > 0 ? '<circle cx="' + cx + '" cy="' + cy + '" r="' + covR.toFixed(1) + '" fill="rgba(52,210,122,0.06)" stroke="#34d27a" stroke-width="1.6"/>' : "") +
      '<g class="scope-sweep" style="transform-origin:110px 110px"><path d="M110 110 L110 18 A92 92 0 0 1 175 45 Z" fill="url(#sweep)"/></g>' +
      '<circle cx="' + cx + '" cy="' + cy + '" r="3.4" fill="#e4edf3"/>' +
      '<circle cx="' + cx + '" cy="' + cy + '" r="7" fill="none" stroke="#e4edf3" stroke-width="1" opacity="0.5"/>' +
      "</svg>";
    return '<div class="scope-wrap"><div class="scope">' + svg + "</div>" +
      '<div class="scope-legend">' +
        '<div class="lg"><span class="sw" style="border-color:#34d27a"></span>Coverage<span class="val">' + Math.round(cov) + "m</span></div>" +
        '<div class="lg"><span class="sw" style="border-color:#f4b13a;border-top-style:dashed"></span>Airspace<span class="val">' + (air > 0 ? Math.round(air) + "m" : "off") + "</span></div>" +
        '<div class="lg"><span class="sw" style="border-color:#e4edf3"></span>Tower<span class="val">H ' + a.atc.coords.w.toFixed(0) + "</span></div>" +
      "</div></div>";
  }

  function renderRunways(a) {
    var body = "";
    if (!a.runways.length) {
      body = '<div class="empty"><div class="big">No runways yet</div><p>Add a runway, then draw its surface and the trigger zones that line up with departures and arrivals.</p>' +
        '<button class="btn btn--primary" data-act="add-runway">Add runway</button></div>';
    } else {
      a.runways.forEach(function (r, i) {
        var active = state.runwayIndex === i;
        var surfaceSet = r.zone || (r.points && r.points.length >= 3);
        var sub = RUNWAY_ZONE_KEYS.map(function (k) {
          var z = zoneOf(r, k);
          return '<div class="row"><div class="row-main"><div class="row-title">' + esc(ZONE_LABELS[k]) +
            '</div><div class="row-sub">' + esc(ZONE_DESC[k]) + "</div></div>" +
            '<div class="row-tools">' + chip(zoneSummary(z)) +
            '<div class="seg">' +
              '<button data-act="place-runway-zone" data-idx="' + i + '" data-key="' + k + '" data-mode="poly">Poly</button>' +
              '<button data-act="place-runway-zone" data-idx="' + i + '" data-key="' + k + '" data-mode="box">Box</button>' +
              '<button data-act="place-runway-zone" data-idx="' + i + '" data-key="' + k + '" data-mode="sphere">Sphere</button>' +
            "</div>" +
            (z ? '<button class="btn btn--danger btn--sm" data-act="clear-runway-zone" data-idx="' + i + '" data-key="' + k + '">Clear</button>' : "") +
            "</div></div>";
        }).join("");

        body += '<div class="unit"><div class="unit-head">' +
          '<input class="title-input" value="' + esc(r.label || ("Runway " + (i + 1))) + '" data-act="rename-runway" data-idx="' + i + '" />' +
          '<span class="grow"></span>' +
          (active ? '<span class="chip is-set"><span class="dot"></span>Selected</span>' : '<button class="btn btn--sm" data-act="select-runway" data-idx="' + i + '">Select</button>') +
          '<button class="btn btn--sm" data-act="test-runway" data-idx="' + i + '">Test</button>' +
          '<button class="btn btn--danger btn--sm" data-act="remove-runway" data-idx="' + i + '">Remove</button>' +
          "</div><div class=\"unit-body\">" +
          '<div class="row"><div class="row-main"><div class="row-title">Runway surface</div>' +
            '<div class="row-sub">Polygon that marks the paved strip.</div></div>' +
            '<div class="row-tools">' + chip(surfaceSet ? "POLY · " + ((r.points && r.points.length) || (r.zone && r.zone.points && r.zone.points.length) || 0) + " pts" : null) +
            '<button class="btn btn--amber btn--sm" data-act="place-runway-surface" data-idx="' + i + '">Draw surface</button>' +
            '<button class="btn btn--sm" data-act="auto-build-runway" data-idx="' + i + '">Auto build zones</button></div></div>' +
          '<div class="subzones">' + sub + "</div>" +
          "</div></div>";
      });
      body += '<div class="actions"><button class="btn btn--primary" data-act="add-runway">Add runway</button></div>';
    }
    return head("Runways", "Runways & trigger zones", "Each runway carries its own taxi, takeoff, approach and landing zones. Select a runway to preview it in the world.") + body;
  }

  function renderGates(a) {
    var body = "";
    if (!a.gates.length) {
      body = '<div class="empty"><div class="big">No gates yet</div><p>Add a gate, then place its aircraft stand with the gizmo to lock in the spawn position and heading.</p>' +
        '<button class="btn btn--primary" data-act="add-gate">Add gate</button></div>';
    } else {
      a.gates.forEach(function (g, i) {
        var spawnSet = g.aircraftSpawn && (g.aircraftSpawn.x || g.aircraftSpawn.y);
        body += '<div class="unit"><div class="unit-head">' +
          '<input class="title-input" value="' + esc(g.label || ("Gate " + (i + 1))) + '" data-act="rename-gate" data-idx="' + i + '" />' +
          '<span class="grow"></span>' + chip(spawnSet ? "Stand set" : null) +
          '<button class="btn btn--danger btn--sm" data-act="remove-gate" data-idx="' + i + '">Remove</button>' +
          '</div><div class="unit-body"><div class="grid grid--3">' +
            gateField("Gate code", g.gate || "A1", i, "gate") +
            gateField("Aircraft model", g.aircraftModel || "shamal", i, "aircraftModel") +
            gateField("Boarding radius", (g.aircraftBoardingRadius == null ? 28 : g.aircraftBoardingRadius), i, "aircraftBoardingRadius", true) +
          "</div>" +
          (spawnSet ? '<div class="readout" style="margin:14px 0 0">Stand: <b>' +
            vec(g.aircraftSpawn).x.toFixed(2) + " " + vec(g.aircraftSpawn).y.toFixed(2) + " " + vec(g.aircraftSpawn).z.toFixed(2) +
            "</b> / H " + vec(g.aircraftSpawn).w.toFixed(1) + "</div>" : "") +
          '<div class="actions"><button class="btn btn--amber" data-act="place-gate" data-idx="' + i + '">' +
            (spawnSet ? "Reposition stand (gizmo)" : "Place stand (gizmo)") + "</button></div>" +
          "</div></div>";
      });
      body += '<div class="actions"><button class="btn btn--primary" data-act="add-gate">Add gate</button></div>';
    }
    return head("Gates", "Gates & aircraft stands", "Boarding gates and the aircraft spawn that serves them. Stand placement uses object_gizmo for precise heading.") + body;
  }

  function renderZones(a) {
    var rows = ZONE_KEYS.map(function (k) {
      var z = zoneOf(a, k);
      return '<div class="row"><div class="row-main"><div class="row-title">' + esc(ZONE_LABELS[k]) + " · " +
        '<span class="muted" style="font-family:var(--mono);font-size:10.5px">' + k + "</span></div>" +
        '<div class="row-sub">' + esc(ZONE_DESC[k]) + "</div></div>" +
        '<div class="row-tools">' + chip(zoneSummary(z)) +
        '<div class="seg">' +
          '<button data-act="place-zone" data-key="' + k + '" data-mode="poly">Poly</button>' +
          '<button data-act="place-zone" data-key="' + k + '" data-mode="box">Box</button>' +
          '<button data-act="place-zone" data-key="' + k + '" data-mode="sphere">Sphere</button>' +
        "</div>" +
        (z ? '<button class="btn btn--danger btn--sm" data-act="clear-zone" data-key="' + k + '">Clear</button>' : "") +
        "</div></div>";
    }).join("");
    return head("ATC trigger zones", "Airport trigger zones", "Taxi hold, takeoff, approach, landing and arrival zones drive the ATC callouts and flight-state changes.") +
      '<div class="card" style="padding:16px">' + rows + "</div>";
  }

  function renderBlip(a) {
    var color = blipColor(a.blip.color);
    return head("Map blip", "Map presence", "How this station shows up on the map. Sprite and color follow GTA blip IDs.") +
      '<div class="card"><div class="card-head"><span class="label">Blip</span></div>' +
      '<div class="flex flex-wrap" style="gap:24px;margin-bottom:16px">' +
        toggle("Show blip on map", a.blip.enabled !== false, "blip.enabled") +
      "</div>" +
      '<div class="grid grid--3">' +
        field("Sprite ID", a.blip.sprite, "blip.sprite", { number: true }) +
        field("Color ID", a.blip.color, "blip.color", { number: true }) +
        field("Scale", a.blip.scale, "blip.scale", { number: true }) +
      "</div>" +
      '<div class="blip-preview" style="margin-top:16px"><div class="blip-dot" style="color:' + color + ';background:' + color + '"></div>' +
        '<div><div style="font-weight:600;font-size:13px">' + esc(a.label || a.id) + '</div>' +
        '<div class="muted" style="font-family:var(--mono);font-size:11px;margin-top:3px">sprite ' + num(a.blip.sprite) + " · color " + num(a.blip.color) + " · scale " + num(a.blip.scale) + "</div></div></div>" +
      "</div>";
  }

  function renderRestricted(a) {
    var on = a.restricted === true;
    return head("Restricted airspace", "Restricted controls", "Mark this station as restricted to enforce no-fly behaviour and warn pilots who enter.") +
      (on ? '<div class="banner is-danger"><span class="ico">▲</span><div>Restricted airspace is active. Pilots entering the controlled zone will be warned and tracked.</div></div>'
          : '<div class="banner"><span class="ico">●</span><div>This station is open. Enable restriction below to enforce a no-fly zone.</div></div>') +
      '<div class="card"><div class="card-head"><span class="label">Enforcement</span></div>' +
      '<div class="flex" style="margin-bottom:16px">' + toggle("Restricted airspace", on, "restricted") + "</div>" +
      '<div class="field col-2"><label>Warning message</label>' +
        '<textarea data-bind="restrictedMessage" data-type="text" placeholder="Restricted military airspace. Leave the area immediately.">' +
        esc(a.restrictedMessage || "") + "</textarea>" +
        '<span class="hint">Shown to pilots who enter the restricted zone.</span></div>' +
      "</div>";
  }

  // ---------- field builders ----------
  function field(label, value, bind, opt) {
    opt = opt || {};
    var attrs = bind ? ' data-bind="' + bind + '" data-type="' + (opt.number ? "number" : "text") + '"' : "";
    var ro = opt.readonly ? " readonly" : "";
    var cls = opt.col2 ? "field col-2" : "field";
    return '<div class="' + cls + '"><label>' + esc(label) + "</label>" +
      '<input value="' + esc(value) + '"' + attrs + ro + ' autocomplete="off" spellcheck="false" />' +
      (opt.hint ? '<span class="hint">' + esc(opt.hint) + "</span>" : "") + "</div>";
  }
  function gateField(label, value, idx, key, isNum) {
    return '<div class="field"><label>' + esc(label) + "</label>" +
      '<input value="' + esc(value) + '" data-act="edit-gate" data-idx="' + idx + '" data-key="' + key +
      '" data-type="' + (isNum ? "number" : "text") + '" autocomplete="off" spellcheck="false" /></div>';
  }
  function selectField(label, value, bind, options, opt) {
    opt = opt || {};
    var opts = options.map(function (o) {
      return '<option value="' + esc(o[0]) + '"' + (String(value) === String(o[0]) ? " selected" : "") + ">" + esc(o[1]) + "</option>";
    }).join("");
    return '<div class="field"><label>' + esc(label) + "</label>" +
      '<select data-bind="' + bind + '" data-type="' + (opt.bool ? "bool" : "text") + '">' + opts + "</select></div>";
  }
  function toggle(label, checked, bind) {
    return '<label class="switch"><input type="checkbox" data-bind="' + bind + '" data-type="bool"' +
      (checked ? " checked" : "") + ' /><span class="track"></span><span class="switch-label">' + esc(label) + "</span></label>";
  }

  function blipColor(id) {
    var map = { 0: "#9a9a9a", 1: "#e74c3c", 2: "#34d27a", 3: "#3aa0f4", 4: "#f4b13a", 5: "#f4e23a", 38: "#3aa0f4", 47: "#7a5cff", 66: "#f49a3a" };
    return map[num(id)] || "#3aa0f4";
  }

  // ============================================================
  //  RENDER
  // ============================================================
  function render() {
    var a = current();
    // station select
    var sel = $("#stationSelect");
    sel.innerHTML = state.airports.map(function (ap) {
      return '<option value="' + esc(ap.id) + '"' + (ap.id === state.currentId ? " selected" : "") + ">" + esc(ap.label || ap.id) + "</option>";
    }).join("");

    // rail active
    Array.prototype.forEach.call(document.querySelectorAll(".rail .tab"), function (t) {
      t.classList.toggle("active", t.getAttribute("data-tab") === state.tab);
    });

    var content = $("#content");
    if (!a) {
      content.innerHTML = '<div class="empty" style="margin-top:40px"><div class="big">No station selected</div>' +
        '<p>Create a station to begin building an airport.</p>' +
        '<button class="btn btn--primary" data-act="open-new">New airport</button></div>';
      return;
    }

    if (state.runwayIndex >= a.runways.length) state.runwayIndex = Math.max(0, a.runways.length - 1);

    var map = {
      overview: renderOverview, atc: renderATC, runways: renderRunways,
      gates: renderGates, zones: renderZones, blip: renderBlip, restricted: renderRestricted
    };
    content.innerHTML = (map[state.tab] || renderOverview)(a);
    content.scrollTop = content.__keepScroll || 0;
  }

  // ============================================================
  //  EVENTS
  // ============================================================
  function withAirportId(data) { data.airportId = state.currentId; return data; }

  function handleAct(act, t) {
    var a = current();
    var idx = t.getAttribute("data-idx");
    var key = t.getAttribute("data-key");
    var mode = t.getAttribute("data-mode");
    idx = idx == null ? null : parseInt(idx, 10);

    switch (act) {
      case "open-new": openModal(); break;

      case "place-atc":
        NUI.post("creatorPlace", withAirportId({ mode: "point", target: "atc" })); break;
      case "current-atc":
        NUI.post("creatorCurrentPoint", withAirportId({ mode: "point", target: "atc" })); break;

      case "place-airspace-poly":
        NUI.post("creatorPlace", withAirportId({ mode: "poly", target: "airspace", zoneKey: "controlledZone", label: "Controlled Airspace" })); break;
      case "delete-airspace-poly":
        if (a && a.airspace) { delete a.airspace.controlledZone; saveAirport(true); } break;

      case "test-airport":
        NUI.post("creatorTestAirport", { airport: a, runwayIndex: state.runwayIndex, directionIndex: 0 }); break;
      case "test-runway":
        NUI.post("creatorTestAirport", { airport: a, runwayIndex: idx, directionIndex: 0 }); break;

      case "add-runway":
        a.runways.push({ label: "Runway " + (a.runways.length + 1), zones: {} });
        state.runwayIndex = a.runways.length - 1; markUnsaved(); saveAirport(true); break;
      case "remove-runway":
        a.runways.splice(idx, 1); markUnsaved(); saveAirport(true); break;
      case "select-runway":
        state.runwayIndex = idx; sendSelection(); render(); break;
      case "place-runway-surface":
        state.runwayIndex = idx; NUI.post("creatorPlace", withAirportId({ mode: "poly", target: "runway", index: idx, runwayIndex: idx })); break;
      case "auto-build-runway":
        state.runwayIndex = idx;
        if (a.runways[idx] && autoBuildRunwayZones(a.runways[idx], idx)) {
          markUnsaved();
          sendSelection();
          saveAirport(true);
        } else {
          setStatus("error", "Draw runway first");
          render();
        }
        break;
      case "place-runway-zone":
        state.runwayIndex = idx;
        NUI.post("creatorPlace", withAirportId({ mode: mode, target: "runwayZone", zoneKey: key, runwayIndex: idx, index: idx })); break;
      case "clear-runway-zone":
        NUI.post("creatorPatchAirport", { airportId: state.currentId, patch: { action: "zoneDeleted", placement: { target: "runwayZone", zoneKey: key, runwayIndex: idx } } })
          .then(applyPatchResult); break;

      case "add-gate":
        a.gates.push({ label: "Gate " + (a.gates.length + 1), gate: "A" + (a.gates.length + 1), aircraftModel: "shamal", aircraftBoardingRadius: 28 });
        markUnsaved(); saveAirport(true); break;
      case "remove-gate":
        a.gates.splice(idx, 1); markUnsaved(); saveAirport(true); break;
      case "place-gate":
        var g = a.gates[idx] || {};
        NUI.post("creatorPlace", withAirportId({
          mode: "ghostGate", target: "gate", index: idx, gateId: g.id, label: g.label || ("Gate " + (idx + 1)),
          gate: g.gate || "A1", aircraftModel: g.aircraftModel || "shamal",
          aircraftBoardingRadius: g.aircraftBoardingRadius || 28, aircraftSpawn: g.aircraftSpawn || null
        })); break;

      case "place-zone":
        NUI.post("creatorPlace", withAirportId({ mode: mode, target: "zone", zoneKey: key })); break;
      case "clear-zone":
        NUI.post("creatorPatchAirport", { airportId: state.currentId, patch: { action: "zoneDeleted", placement: { target: "zone", zoneKey: key } } })
          .then(applyPatchResult); break;
    }
  }

  function applyPatchResult(res) {
    if (res && res.success && res.result) { replaceAirport(res.result); setStatus("saved"); render(); }
    else if (res && res.success && res.airport) { replaceAirport(res.airport); setStatus("saved"); render(); }
    else { render(); }
  }

  function saveAirport(silent) {
    var a = current();
    if (!a) return;
    setStatus("saving");
    NUI.post("creatorSaveAirport", a).then(function (res) {
      if (res && res.success && res.airport) {
        var keepRunway = state.runwayIndex;
        replaceAirport(res.airport);
        state.runwayIndex = keepRunway;
        setStatus("saved");
        sendSelection();
      } else {
        setStatus("error", (res && res.message) ? "Error" : "Error");
      }
      render();
    });
  }

  function openModal() { $("#modalScrim").classList.add("is-open"); $("#newId").value = ""; $("#newLabel").value = ""; setTimeout(function () { $("#newId").focus(); }, 30); }
  function closeModal() { $("#modalScrim").classList.remove("is-open"); }
  function createAirport() {
    var id = ($("#newId").value || "").trim().toLowerCase().replace(/\s+/g, "");
    var label = ($("#newLabel").value || "").trim();
    if (!id) { $("#newId").focus(); return; }
    for (var i = 0; i < state.airports.length; i++) if (state.airports[i].id === id) { $("#newId").focus(); return; }
    var ap = normalizeAirport({ id: id, label: label || id, tower: (label || id) + " Tower", restricted: false });
    state.airports.push(ap);
    state.currentId = id; state.tab = "atc"; state.runwayIndex = 0;
    closeModal(); markUnsaved(); sendSelection(); render();
  }

  function bindInput(t) {
    var a = current(); if (!a) return;
    var type = t.getAttribute("data-type");
    var bind = t.getAttribute("data-bind");
    var actEdit = t.getAttribute("data-act");

    var value;
    if (type === "bool") value = (t.type === "checkbox") ? t.checked : (t.value === "1" || t.value === "true");
    else if (type === "number") value = num(t.value);
    else value = t.value;

    if (bind) {
      setPath(a, bind, value);
      markUnsaved();
      if (bind.indexOf("airspace.enabled") === 0 || bind.indexOf("airspace.radius") === 0 || bind.indexOf("atc.coverageRadius") === 0 || bind.indexOf("atc.coords") === 0) {
        // keep the in-world preview + radar scope in step
        if (state.tab === "atc") refreshScope(a);
        sendSelection();
      }
      if (bind.indexOf("blip.") === 0 && state.tab === "blip") render();
      if (bind === "restricted") { content_keepScroll(); render(); }
    } else if (actEdit === "edit-gate") {
      var gi = parseInt(t.getAttribute("data-idx"), 10);
      var gk = t.getAttribute("data-key");
      if (a.gates[gi]) { a.gates[gi][gk] = value; markUnsaved(); }
    } else if (actEdit === "rename-runway") {
      var ri = parseInt(t.getAttribute("data-idx"), 10);
      if (a.runways[ri]) { a.runways[ri].label = t.value; markUnsaved(); }
    } else if (actEdit === "rename-gate") {
      var gj = parseInt(t.getAttribute("data-idx"), 10);
      if (a.gates[gj]) { a.gates[gj].label = t.value; markUnsaved(); }
    }
  }

  function content_keepScroll() { var c = $("#content"); c.__keepScroll = c.scrollTop; }

  function refreshScope(a) {
    var wrap = $(".scope-wrap"); if (!wrap) return;
    wrap.outerHTML = scopeBlock(a);
  }

  // ============================================================
  //  Lua -> page
  // ============================================================
  NUI.onMessage(function (msg) {
    switch (msg.action) {
      case "open":
        state.airports = (msg.airports || []).map(normalizeAirport);
        if (!current()) state.currentId = state.airports.length ? state.airports[0].id : null;
        state.tab = state.tab || "overview";
        $("#root").classList.add("is-open");
        setStatus("ready"); render(); sendSelection();
        break;

      case "close":
        $("#root").classList.remove("is-open"); closeModal();
        break;

      case "airports": {
        var locals = state.airports.filter(function (ap) {
          return !(msg.airports || []).some(function (m) { return m.id === ap.id; });
        });
        state.airports = (msg.airports || []).map(normalizeAirport).concat(locals);
        if (!current()) state.currentId = state.airports.length ? state.airports[0].id : null;
        render(); sendSelection();
        break;
      }

      case "pointPlaced": {
        if (msg.saved && msg.airport) { replaceAirport(msg.airport); setStatus("saved"); }
        else {
          var a = current();
          if (a && msg.point) {
            if (msg.target === "atc") { a.atc = a.atc || {}; a.atc.coords = vec(msg.point); markUnsaved(); }
            else if (msg.target === "hangar") { a.hangars = a.hangars || []; a.hangars.push({ label: "Hangar " + (a.hangars.length + 1), coords: vec(msg.point) }); markUnsaved(); }
          }
        }
        render();
        break;
      }

      case "polyPlaced":
      case "zonePlaced":
      case "ghostPlaced":
        if (msg.saved && msg.airport) { replaceAirport(msg.airport); setStatus("saved"); }
        else if (msg.error) { setStatus("error"); }
        render();
        break;
    }
  });

  // ============================================================
  //  DOM wiring
  // ============================================================
  var _inited = false;
  function init() {
    if (_inited) return;
    _inited = true;
    // rail tabs
    Array.prototype.forEach.call(document.querySelectorAll(".rail .tab[data-tab]"), function (t) {
      t.addEventListener("click", function () {
        state.tab = t.getAttribute("data-tab");
        var c = $("#content"); c.__keepScroll = 0;
        render(); sendSelection();
      });
    });

    $("#closeBtn").addEventListener("click", function () { NUI.post("creatorClose", {}); $("#root").classList.remove("is-open"); });
    $("#saveBtn").addEventListener("click", function () { saveAirport(false); });
    $("#newAirportBtn").addEventListener("click", openModal);
    $("#stationSelect").addEventListener("change", function (e) {
      state.currentId = e.target.value; state.runwayIndex = 0; state.tab = state.tab;
      setStatus("ready"); render(); sendSelection();
    });

    // modal
    $("#modalCancel").addEventListener("click", closeModal);
    $("#modalCreate").addEventListener("click", createAirport);
    $("#modalScrim").addEventListener("mousedown", function (e) { if (e.target === $("#modalScrim")) closeModal(); });

    // delegated clicks
    $("#content").addEventListener("click", function (e) {
      var t = e.target.closest("[data-act]");
      if (!t) return;
      var act = t.getAttribute("data-act");
      if (act === "rename-runway" || act === "rename-gate" || act === "edit-gate") return; // inputs
      content_keepScroll();
      handleAct(act, t);
    });

    // delegated input/change for binds + inline edits
    $("#content").addEventListener("input", function (e) {
      var t = e.target;
      if (t.matches("[data-bind], [data-act='edit-gate'], [data-act='rename-runway'], [data-act='rename-gate']")) bindInput(t);
    });
    $("#content").addEventListener("change", function (e) {
      var t = e.target;
      if (t.matches("select[data-bind], input[type='checkbox'][data-bind]")) bindInput(t);
    });

    // Esc closes
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        if ($("#modalScrim").classList.contains("is-open")) { closeModal(); return; }
        NUI.post("creatorClose", {}); $("#root").classList.remove("is-open");
      }
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();

  // expose for dev harness
  window.__aircreator = { state: state, render: render };
})();
