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
    }
};
