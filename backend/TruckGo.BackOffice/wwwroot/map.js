// TruckGo back office — the Map & trace screen (Components/Pages/Map/MapPage.razor).
// Leaflet + OpenStreetMap, like the other maps (app.js). Map instances are
// kept in truckgo.maps so truckgo.removeMap() cleans them up.
window.truckgoMap = (function () {
    "use strict";

    // Plates and names come from the database: never trust them as HTML
    function esc(text) {
        return String(text == null ? "" : text).replace(/[&<>"']/g, function (c) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
        });
    }

    var TRUCK_SVG = '<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M20 8h-3V4H3c-1.1 0-2 .9-2 2v11h2c0 1.66 1.34 3 3 3s3-1.34 3-3h6c0 1.66 1.34 3 3 3s3-1.34 3-3h2v-5l-3-4zM6 18.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm13.5-9 1.96 2.5H17V9.5h2.5zm-1.5 9c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5z"/></svg>';
    var STATE_LABEL = { AtPlant: "At plant", OnTheRoad: "On the road", AtShipTo: "At ship-to", Idle: "Idle" };

    // A new map in the element, with the same tiles and resize handling as app.js
    function newMap(elementId) {
        var element = document.getElementById(elementId);
        if (!element || !window.L) return null;
        truckgo.removeMap(elementId);
        var map = L.map(element, { scrollWheelZoom: true });
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, attribution: "&copy; OpenStreetMap" }).addTo(map);
        setTimeout(function () { map.invalidateSize(); }, 250);
        if (window.ResizeObserver) {
            map._tgResize = new ResizeObserver(function () { map.invalidateSize(); });
            map._tgResize.observe(element);
        }
        truckgo.maps[elementId] = map;
        return map;
    }

    // Plants (blue) and sites (amber) with their geofence circles; a click opens their page
    function drawPlaces(layer, places, radiusM) {
        var colours = { plant: "#2563EB", site: "#F59E0B" };
        places.forEach(function (p) {
            var colour = colours[p.kind] || colours.site;
            L.circle([p.lat, p.lng], { radius: radiusM, color: colour, weight: 1.5, dashArray: "5 5", fillColor: colour, fillOpacity: 0.1 }).addTo(layer);
            var dot = L.circleMarker([p.lat, p.lng], { radius: 6, color: "#fff", weight: 2, fillColor: colour, fillOpacity: 1 }).addTo(layer);
            dot.bindTooltip(esc(p.label), { direction: "top", offset: [0, -6] });
            dot.on("click", function () { go(p.url); });
        });
    }

    function go(url) {
        if (!url) return;
        if (window.Blazor && Blazor.navigateTo) Blazor.navigateTo(url); else window.location.href = url;
    }

    function ago(iso) {
        var minutes = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
        if (minutes < 1) return "just now";
        if (minutes < 60) return minutes + " min ago";
        return Math.floor(minutes / 60) + " h " + ("0" + (minutes % 60)).slice(-2) + " ago";
    }

    // A truck marker: coloured pin with the plate
    function truckIcon(t) {
        return L.divIcon({
            className: "",
            html: '<div class="truck-pin st-' + esc(t.state) + (t.stale ? " stale" : "") + '">' + TRUCK_SVG + "<b>" + esc(t.plate) + "</b></div>",
            iconSize: null,
            iconAnchor: [14, 14],
        });
    }

    function popupFor(t) {
        var html = '<div class="map-pop"><div class="map-pop-title">' + esc(t.plate) + ' <span class="pop-state st-' + esc(t.state) + '">' + STATE_LABEL[t.state] + "</span></div>";
        if (t.deliveryLabel) html += '<div class="map-pop-line">' + esc(t.deliveryLabel) + "</div>";
        html += '<div class="map-pop-muted">Seen ' + ago(t.at) + (t.speedKmh != null && t.speedKmh > 3 ? " · " + Math.round(t.speedKmh) + " km/h" : "") + "</div>";
        html += '<div class="map-pop-links">';
        if (t.deliveryId) {
            html += '<a href="/deliveries/' + esc(t.deliveryId) + '">Delivery</a>';
            html += '<a href="/map?delivery=' + esc(t.deliveryId) + '">Route</a>';
        } else {
            html += '<a href="/map?truck=' + encodeURIComponent(t.plate) + '">Today\'s route</a>';
        }
        if (t.vehicleId) html += '<a href="/vehicles/' + esc(t.vehicleId) + '">Truck</a>';
        return html + "</div></div>";
    }

    return {
        // LIVE: draws (or refreshes) the trucks at their last point. The view
        // is fitted only the first time, so a refresh does not move the map.
        live: function (elementId, trucks, places, radiusM) {
            var map = truckgo.maps[elementId];
            var first = !map || !map._tgLive;
            if (first) {
                map = newMap(elementId);
                if (!map) return;
                map._tgLive = { places: L.layerGroup().addTo(map), trucks: L.layerGroup().addTo(map), markers: {} };
            }
            var live = map._tgLive;
            live.places.clearLayers();
            live.trucks.clearLayers();
            live.markers = {};
            drawPlaces(live.places, places, radiusM);
            trucks.forEach(function (t) {
                var m = L.marker([t.lat, t.lng], { icon: truckIcon(t), zIndexOffset: t.state === "Idle" ? 0 : 1000 }).addTo(live.trucks);
                m.bindPopup(popupFor(t), { minWidth: 220 });
                live.markers[t.plate] = m;
            });
            if (first) {
                var all = trucks.map(function (t) { return [t.lat, t.lng]; }).concat(places.map(function (p) { return [p.lat, p.lng]; }));
                if (all.length > 1) map.fitBounds(all, { padding: [50, 50], maxZoom: 14 });
                else if (all.length === 1) map.setView(all[0], 14);
                else map.setView([52.4, -1.5], 9);
            }
        },

        // LIVE: centre on one truck and open its popup (from the list next to the map)
        focusTruck: function (elementId, plate) {
            var map = truckgo.maps[elementId];
            var m = map && map._tgLive && map._tgLive.markers[plate];
            if (!m) return;
            map.setView(m.getLatLng(), Math.max(map.getZoom(), 13));
            m.openPopup();
        },

        // TRACE: the route, start and end, the unexpected stops, and the replay truck
        trace: function (elementId, points, places, stops, radiusM, plate) {
            var map = newMap(elementId);
            if (!map) return;
            var layer = L.layerGroup().addTo(map);
            drawPlaces(layer, places, radiusM);
            var line = points.map(function (p) { return [p.lat, p.lng]; });
            if (line.length > 1) {
                L.polyline(line, { color: "#fff", weight: 8, opacity: 0.9 }).addTo(layer);  // white edge
                L.polyline(line, { color: "#2563EB", weight: 4.5, opacity: 0.95 }).addTo(layer);
            }
            if (line.length > 0) {
                L.marker(line[0], { icon: L.divIcon({ className: "", html: '<div class="trace-end trace-start">A</div>', iconAnchor: [11, 11] }) })
                    .bindTooltip("Start", { direction: "top" }).addTo(layer);
                L.marker(line[line.length - 1], { icon: L.divIcon({ className: "", html: '<div class="trace-end trace-finish">B</div>', iconAnchor: [11, 11] }) })
                    .bindTooltip("Last point", { direction: "top" }).addTo(layer);
            }
            stops.forEach(function (s) {
                L.marker([s.lat, s.lng], { icon: L.divIcon({ className: "", html: '<div class="trace-stop">' + Math.round(s.minutes) + "′</div>", iconAnchor: [16, 12] }) })
                    .bindTooltip("Stopped " + Math.round(s.minutes) + " min", { direction: "top" }).addTo(layer);
            });
            // The truck that moves with the replay slider
            map._tgTrace = {
                points: line,
                truck: line.length ? L.marker(line[0], {
                    icon: truckIcon({ state: "OnTheRoad", plate: plate || "", stale: false }), zIndexOffset: 2000
                }).addTo(map) : null,
            };
            var bounds = line.concat(places.map(function (p) { return [p.lat, p.lng]; }));
            if (bounds.length > 1) map.fitBounds(bounds, { padding: [40, 40], maxZoom: 15 });
            else if (bounds.length === 1) map.setView(bounds[0], 14);
            else map.setView([52.4, -1.5], 9);
        },

        // TRACE: the replay slider moved: put the truck on point "index"
        cursor: function (elementId, index) {
            var map = truckgo.maps[elementId];
            var t = map && map._tgTrace;
            if (!t || !t.truck || !t.points[index]) return;
            t.truck.setLatLng(t.points[index]);
        },
    };
})();
