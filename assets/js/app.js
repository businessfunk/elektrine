// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Import our custom home page JavaScript
import "./home.js"

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#F2C029"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Mobile menu toggle
document.addEventListener("DOMContentLoaded", () => {
  const mobileMenuButton = document.querySelector('[aria-controls="mobile-menu"]');
  const mobileMenu = document.getElementById('mobile-menu');
  
  if (mobileMenuButton && mobileMenu) {
    mobileMenuButton.addEventListener('click', () => {
      const expanded = mobileMenuButton.getAttribute('aria-expanded') === 'true';
      mobileMenuButton.setAttribute('aria-expanded', !expanded);
      mobileMenu.classList.toggle('hidden');
      
      // Toggle the menu icons
      const openIcon = mobileMenuButton.querySelector('svg:first-of-type');
      const closeIcon = mobileMenuButton.querySelector('svg:last-of-type');
      
      if (openIcon && closeIcon) {
        openIcon.classList.toggle('hidden');
        closeIcon.classList.toggle('hidden');
      }
    });
  }
});

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken}
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Auto-dismiss flash messages after 5 seconds
window.addEventListener("elektrine:flash-auto-dismiss", (e) => {
  const flashElement = e.target;
  const dismissTimeout = setTimeout(() => {
    const event = new Event("click", { bubbles: true });
    flashElement.dispatchEvent(event);
  }, 5000); // 5 seconds - must match the CSS animation duration

  // Clear timeout if user manually dismisses the flash
  flashElement.addEventListener("click", () => {
    clearTimeout(dismissTimeout);
  }, { once: true });

  // Pause animation on hover
  flashElement.addEventListener("mouseenter", () => {
    const progressBar = flashElement.querySelector(".flash-progress");
    if (progressBar) {
      progressBar.style.animationPlayState = "paused";
      clearTimeout(dismissTimeout);
    }
  });

  // Resume animation on mouse leave
  flashElement.addEventListener("mouseleave", () => {
    const progressBar = flashElement.querySelector(".flash-progress");
    if (progressBar) {
      progressBar.style.animationPlayState = "running";
      
      // Calculate remaining time based on progress bar width
      const progressBarWidth = parseInt(window.getComputedStyle(progressBar).width);
      const containerWidth = parseInt(window.getComputedStyle(flashElement).width);
      const remainingPercentage = progressBarWidth / containerWidth;
      const remainingTime = remainingPercentage * 5000;
      
      // Reset the timeout with the remaining time
      clearTimeout(dismissTimeout);
      if (remainingTime > 0) {
        setTimeout(() => {
          const event = new Event("click", { bubbles: true });
          flashElement.dispatchEvent(event);
        }, remainingTime);
      }
    }
  });
});

