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
import { initGenerativeArt, initDigitalEffects } from "./generative_art"

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
  },
  InboxDebug: {
    mounted() {
      console.log("InboxDebug hook mounted on:", this.el)
      window.addEventListener("phx:inbox-updated", (e) => {
        console.log("Inbox updated event received:", e.detail)
        console.log("Current message count in DOM:", this.el.querySelectorAll('[id^="message-"]').length)
      })
    },
    updated() {
      console.log("InboxDebug hook updated")
      console.log("Message count after update:", this.el.querySelectorAll('[id^="message-"]').length)
    }
  },
  FocusOnMount: {
    mounted() {
      // Focus on the textarea when mounted
      this.el.focus()
      
      // Add event listener to combine new message with original when form is submitted
      const form = this.el.closest('form')
      if (form) {
        form.addEventListener('submit', (e) => {
          const newMessage = this.el.value.trim()
          const hiddenBodyField = form.querySelector('#full-message-body')
          const originalMessage = hiddenBodyField.value
          
          // Combine new message with original
          if (newMessage) {
            hiddenBodyField.value = newMessage + originalMessage
          } else {
            // If no new message, just use original (for forwarding without adding text)
            hiddenBodyField.value = originalMessage
          }
        })
      }
    }
  },
  MarkdownEditor: {
    mounted() {
      this.setupToolbar('#html-editor', 'preview-panel', 'preview-content')
      this.setupPreview('#html-editor', 'preview-panel', 'preview-content')
      
      // Also setup toolbar for any reply/forward toolbars
      this.setupReplyToolbars()
    },
    
    setupToolbar(targetSelector, previewPanelId, previewContentId) {
      const toolbar = document.querySelector('[data-format]:not([data-target])')?.closest('.flex')
      if (!toolbar) return
      
      toolbar.addEventListener('click', (e) => {
        const button = e.target.closest('[data-format], [data-action]')
        if (!button) return
        
        e.preventDefault()
        
        if (button.dataset.format) {
          this.insertFormat(button.dataset.format, targetSelector)
        } else if (button.dataset.action === 'preview') {
          this.togglePreview(targetSelector, previewPanelId, previewContentId)
        }
      })
    },
    
    setupReplyToolbars() {
      // Setup toolbar for reply/forward mode (with data-target attributes)
      const replyToolbar = document.querySelector('[data-target="new-message-area"]')?.closest('.flex')
      if (!replyToolbar) return
      
      replyToolbar.addEventListener('click', (e) => {
        const button = e.target.closest('[data-format], [data-action]')
        if (!button) return
        
        e.preventDefault()
        
        const targetId = button.dataset.target
        if (!targetId) return
        
        const targetElement = document.getElementById(targetId)
        if (!targetElement) return
        
        if (button.dataset.format) {
          this.insertFormatInTarget(button.dataset.format, targetElement)
        } else if (button.dataset.action === 'preview') {
          this.toggleReplyPreview(targetElement)
        }
      })
    },
    
    insertFormatInTarget(format, textarea) {
      const start = textarea.selectionStart
      const end = textarea.selectionEnd
      const selectedText = textarea.value.substring(start, end)
      let replacement = ''
      
      switch (format) {
        case 'bold':
          replacement = `**${selectedText || 'bold text'}**`
          break
        case 'italic':
          replacement = `*${selectedText || 'italic text'}*`
          break
        case 'underline':
          replacement = `<u>${selectedText || 'underlined text'}</u>`
          break
        case 'heading':
          replacement = `# ${selectedText || 'Heading'}`
          break
        case 'link':
          const url = selectedText.startsWith('http') ? selectedText : 'https://example.com'
          const linkText = selectedText.startsWith('http') ? 'link text' : selectedText || 'link text'
          replacement = `[${linkText}](${url})`
          break
        case 'list':
          replacement = `- ${selectedText || 'list item'}`
          break
        case 'quote':
          replacement = `> ${selectedText || 'quoted text'}`
          break
      }
      
      textarea.value = textarea.value.substring(0, start) + replacement + textarea.value.substring(end)
      textarea.focus()
      
      // Set cursor position
      const newPos = start + replacement.length
      textarea.setSelectionRange(newPos, newPos)
    },
    
    toggleReplyPreview(textarea) {
      const previewPanel = document.getElementById('reply-preview-panel')
      const previewContent = document.getElementById('reply-preview-content')
      
      if (!previewPanel || !previewContent) return
      
      if (previewPanel.classList.contains('hidden')) {
        // Show preview
        const markdown = textarea.value
        const html = this.markdownToHtml(markdown)
        previewContent.innerHTML = html
        previewPanel.classList.remove('hidden')
      } else {
        // Hide preview
        previewPanel.classList.add('hidden')
      }
    },
    
    insertFormat(format, targetSelector = null) {
      const textarea = targetSelector ? document.querySelector(targetSelector) : this.el
      if (!textarea) return
      
      const start = textarea.selectionStart
      const end = textarea.selectionEnd
      const selectedText = textarea.value.substring(start, end)
      let replacement = ''
      
      switch (format) {
        case 'bold':
          replacement = `**${selectedText || 'bold text'}**`
          break
        case 'italic':
          replacement = `*${selectedText || 'italic text'}*`
          break
        case 'underline':
          replacement = `<u>${selectedText || 'underlined text'}</u>`
          break
        case 'heading':
          replacement = `# ${selectedText || 'Heading'}`
          break
        case 'link':
          const url = selectedText.startsWith('http') ? selectedText : 'https://example.com'
          const linkText = selectedText.startsWith('http') ? 'link text' : selectedText || 'link text'
          replacement = `[${linkText}](${url})`
          break
        case 'list':
          replacement = `- ${selectedText || 'list item'}`
          break
        case 'quote':
          replacement = `> ${selectedText || 'quoted text'}`
          break
      }
      
      textarea.value = textarea.value.substring(0, start) + replacement + textarea.value.substring(end)
      textarea.focus()
      
      // Set cursor position
      const newPos = start + replacement.length
      textarea.setSelectionRange(newPos, newPos)
    },
    
    togglePreview(targetSelector = null, previewPanelId = 'preview-panel', previewContentId = 'preview-content') {
      const textarea = targetSelector ? document.querySelector(targetSelector) : this.el
      const previewPanel = document.getElementById(previewPanelId)
      const previewContent = document.getElementById(previewContentId)
      
      if (!textarea || !previewPanel || !previewContent) return
      
      if (previewPanel.classList.contains('hidden')) {
        // Show preview
        const markdown = textarea.value
        const html = this.markdownToHtml(markdown)
        previewContent.innerHTML = html
        previewPanel.classList.remove('hidden')
      } else {
        // Hide preview
        previewPanel.classList.add('hidden')
      }
    },
    
    markdownToHtml(markdown) {
      return markdown
        // Headers
        .replace(/^### (.*$)/gm, '<h3>$1</h3>')
        .replace(/^## (.*$)/gm, '<h2>$1</h2>')
        .replace(/^# (.*$)/gm, '<h1>$1</h1>')
        // Bold
        .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
        // Italic
        .replace(/\*(.*?)\*/g, '<em>$1</em>')
        // Links
        .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" class="text-primary underline">$1</a>')
        // Lists
        .replace(/^- (.*$)/gm, '<li>$1</li>')
        .replace(/(<li>.*<\/li>)/s, '<ul class="list-disc list-inside">$1</ul>')
        // Quotes
        .replace(/^> (.*$)/gm, '<blockquote class="border-l-4 border-primary pl-4 italic">$1</blockquote>')
        // Line breaks
        .replace(/\n/g, '<br>')
    },
    
    setupPreview(targetSelector = null, previewPanelId = 'preview-panel', previewContentId = 'preview-content') {
      const textarea = targetSelector ? document.querySelector(targetSelector) : this.el
      if (!textarea) return
      
      // Auto-update preview if it's visible
      textarea.addEventListener('input', () => {
        const previewPanel = document.getElementById(previewPanelId)
        const previewContent = document.getElementById(previewContentId)
        if (previewPanel && !previewPanel.classList.contains('hidden')) {
          const html = this.markdownToHtml(textarea.value)
          previewContent.innerHTML = html
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

// Global markdown toolbar handler
document.addEventListener('DOMContentLoaded', () => {
  // Handle all markdown toolbar buttons globally
  document.addEventListener('click', (e) => {
    const button = e.target.closest('[data-format], [data-action]')
    if (!button) return
    
    // Only handle toolbar buttons (inside toolbar containers)
    const toolbar = button.closest('.flex')
    if (!toolbar || !toolbar.querySelector('[data-format]')) return
    
    e.preventDefault()
    
    let targetTextarea = null
    
    // Determine which textarea to target
    if (button.dataset.target) {
      // Reply/Forward mode - use data-target
      targetTextarea = document.getElementById(button.dataset.target)
    } else {
      // Compose mode - find the nearby textarea
      targetTextarea = document.getElementById('html-editor')
    }
    
    if (!targetTextarea) return
    
    if (button.dataset.format) {
      insertMarkdownFormat(button.dataset.format, targetTextarea)
    } else if (button.dataset.action === 'preview') {
      toggleMarkdownPreview(targetTextarea, button.dataset.target)
    }
  })
})

function insertMarkdownFormat(format, textarea) {
  const start = textarea.selectionStart
  const end = textarea.selectionEnd
  const selectedText = textarea.value.substring(start, end)
  let replacement = ''
  
  switch (format) {
    case 'bold':
      replacement = `**${selectedText || 'bold text'}**`
      break
    case 'italic':
      replacement = `*${selectedText || 'italic text'}*`
      break
    case 'underline':
      replacement = `<u>${selectedText || 'underlined text'}</u>`
      break
    case 'heading':
      replacement = `# ${selectedText || 'Heading'}`
      break
    case 'link':
      const url = selectedText.startsWith('http') ? selectedText : 'https://example.com'
      const linkText = selectedText.startsWith('http') ? 'link text' : selectedText || 'link text'
      replacement = `[${linkText}](${url})`
      break
    case 'list':
      replacement = `- ${selectedText || 'list item'}`
      break
    case 'quote':
      replacement = `> ${selectedText || 'quoted text'}`
      break
  }
  
  textarea.value = textarea.value.substring(0, start) + replacement + textarea.value.substring(end)
  textarea.focus()
  
  // Set cursor position
  const newPos = start + replacement.length
  textarea.setSelectionRange(newPos, newPos)
}

function toggleMarkdownPreview(textarea, targetId) {
  let previewPanelId = 'preview-panel'
  let previewContentId = 'preview-content'
  
  // Use reply preview for reply/forward mode
  if (targetId === 'new-message-area') {
    previewPanelId = 'reply-preview-panel'
    previewContentId = 'reply-preview-content'
  }
  
  const previewPanel = document.getElementById(previewPanelId)
  const previewContent = document.getElementById(previewContentId)
  
  if (!previewPanel || !previewContent) return
  
  if (previewPanel.classList.contains('hidden')) {
    // Show preview
    const markdown = textarea.value
    const html = markdownToHtml(markdown)
    previewContent.innerHTML = html
    previewPanel.classList.remove('hidden')
  } else {
    // Hide preview
    previewPanel.classList.add('hidden')
  }
}

function markdownToHtml(markdown) {
  return markdown
    // Headers
    .replace(/^### (.*$)/gm, '<h3>$1</h3>')
    .replace(/^## (.*$)/gm, '<h2>$1</h2>')
    .replace(/^# (.*$)/gm, '<h1>$1</h1>')
    // Bold
    .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
    // Italic
    .replace(/\*(.*?)\*/g, '<em>$1</em>')
    // Links
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" class="text-primary underline">$1</a>')
    // Lists
    .replace(/^- (.*$)/gm, '<li>$1</li>')
    .replace(/(<li>.*<\/li>)/s, '<ul class="list-disc list-inside">$1</ul>')
    // Quotes
    .replace(/^> (.*$)/gm, '<blockquote class="border-l-4 border-primary pl-4 italic">$1</blockquote>')
    // Line breaks
    .replace(/\n/g, '<br>')
}

// Auto-hide all flash messages and initialize homepage effects
document.addEventListener('DOMContentLoaded', () => {
  // Initialize generative art and digital effects for homepage
  initGenerativeArt()
  initDigitalEffects()
  
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