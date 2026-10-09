// TruckGo back office — the few browser helpers the pages call.
window.truckgo = {
    // Submits a normal HTML form by id (used by "Log out", see MainLayout.razor)
    submitForm: function (id) {
        document.getElementById(id).submit();
    },

    // Shows or hides a password field (the eye button on the login page)
    togglePassword: function (id, button) {
        var input = document.getElementById(id);
        var show = input.type === "password";
        input.type = show ? "text" : "password";
        button.classList.toggle("is-on", show);
        button.setAttribute("aria-label", show ? "Hide password" : "Show password");
        input.focus();
    },

    // The side menu: open or folded, remembered in this browser only.
    // Storage can be blocked (private window...): then fall back to the screen size.
    menuOpen: function () {
        try {
            var saved = localStorage.getItem("truckgo.menuOpen");
            if (saved !== null) return saved === "1";
        } catch (e) { }
        return window.innerWidth >= 960;
    },

    rememberMenu: function (open) {
        try { localStorage.setItem("truckgo.menuOpen", open ? "1" : "0"); } catch (e) { }
    },

    // ---- Maps (Leaflet + OpenStreetMap), used by Components/Shared/MapView.razor ----
    //
    // places: [{ lat, lng, label, kind: "site" | "plant", active, url }]
    // Every place gets its geofence circle (radiusM, the company setting).
    // Clicking a place with a url opens that page inside the back office.
    maps: {},

    showMap: function (elementId, places, radiusM) {
        var element = document.getElementById(elementId);
        if (!element || !window.L) return;
        this.removeMap(elementId);

        var map = L.map(element, { scrollWheelZoom: false }); // the page scrolls, not the map
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
            maxZoom: 19,
            attribution: "&copy; OpenStreetMap"
        }).addTo(map);

        var colours = { site: "#F59E0B", plant: "#2563EB" };
        var corners = [];
        places.forEach(function (p) {
            var colour = p.active ? (colours[p.kind] || colours.site) : "#94A3B8";
            L.circle([p.lat, p.lng], {
                radius: radiusM, color: colour, weight: 1.5, dashArray: "5 5", fillColor: colour, fillOpacity: 0.12
            }).addTo(map);
            var dot = L.circleMarker([p.lat, p.lng], {
                radius: 8, color: "#fff", weight: 3, fillColor: colour, fillOpacity: 1
            }).addTo(map);
            dot.bindTooltip(p.label, { direction: "top", offset: [0, -8] });
            if (p.url) {
                dot.on("click", function () {
                    if (window.Blazor && Blazor.navigateTo) Blazor.navigateTo(p.url);
                    else window.location.href = p.url;
                });
            }
            corners.push([p.lat, p.lng]);
        });

        if (corners.length === 1) map.setView(corners[0], 16);
        else if (corners.length > 1) map.fitBounds(corners, { padding: [48, 48], maxZoom: 16 });
        else map.setView([52.4, -1.5], 9);

        // Leaflet measures its box once; when the box changes size (page
        // layout settling, phone rotated, menu folded) it must measure again
        setTimeout(function () { map.invalidateSize(); }, 250);
        if (window.ResizeObserver) {
            map._tgResize = new ResizeObserver(function () { map.invalidateSize(); });
            map._tgResize.observe(element);
        }

        this.maps[elementId] = map;
    },

    removeMap: function (elementId) {
        if (this.maps[elementId]) {
            if (this.maps[elementId]._tgResize) this.maps[elementId]._tgResize.disconnect();
            this.maps[elementId].remove();
            delete this.maps[elementId];
        }
    }
};
