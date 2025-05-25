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

// Define hooks for custom JavaScript behaviors
const Hooks = {
  CopyToClipboard: {
    mounted() {
      this.el.addEventListener("click", e => {
        const emailElement = document.getElementById('email-address')
        if (emailElement) {
          const emailText = emailElement.textContent
          navigator.clipboard.writeText(emailText).then(() => {
            // Show success feedback (change button icon temporarily)
            const originalHTML = this.el.innerHTML
            this.el.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" /></svg>'
            
            // Restore original icon after a delay
            setTimeout(() => {
              this.el.innerHTML = originalHTML
            }, 2000)
          })
        }
      })
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Auto-hide all flash messages
document.addEventListener('DOMContentLoaded', () => {
  // Find all flash messages (using data-auto-hide attribute)
  const flashElements = document.querySelectorAll('[data-auto-hide]')

  flashElements.forEach(flashElement => {
    setTimeout(() => {
      // Add transition classes - only fade out, no translation/movement
      flashElement.classList.add(
        'transition-opacity',
        'duration-300',
        'ease-in'
      )

      // Fade out
      flashElement.style.opacity = "0"

      // Remove from DOM after transition
      setTimeout(() => {
        flashElement.remove()
      }, 300)
    }, 3000) // Hide after 3 seconds
  })
})