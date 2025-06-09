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
  FlashMessage: {
    mounted() {
      // Add slide-in animation immediately
      this.el.classList.add('slide-in-left')
      
      // Find and start progress bar animation
      this.progressBar = this.el.querySelector('.flash-progress')
      if (this.progressBar) {
        // Start progress bar animation after slide-in completes
        setTimeout(() => {
          this.progressBar.classList.add('animate')
        }, 400)
      }
      
      // Set up auto-hide timer
      this.autoHideTimer = setTimeout(() => {
        this.hideWithClear()
      }, 5000)
      
      // Handle click to dismiss
      this.el.addEventListener('click', () => {
        this.hideWithClear()
      })
    },
    
    destroyed() {
      // Clear timer if element is destroyed
      if (this.autoHideTimer) {
        clearTimeout(this.autoHideTimer)
      }
    },
    
    hideWithClear() {
      // Clear any existing timer
      if (this.autoHideTimer) {
        clearTimeout(this.autoHideTimer)
        this.autoHideTimer = null
      }
      
      // Stop progress bar animation
      if (this.progressBar) {
        this.progressBar.classList.remove('animate')
      }
      
      // Extract the flash type from the element ID (flash-info or flash-error)
      const flashType = this.el.id.replace('flash-', '')
      
      // Clear the flash from LiveView state
      this.pushEvent("lv:clear-flash", {key: flashType})
      
      // Start hide animation
      this.hide()
    },
    
    hide() {
      // Add slide-out animation
      this.el.classList.remove('slide-in-left')
      this.el.classList.add('slide-out-left')
      
      // Remove element after animation
      setTimeout(() => {
        if (this.el && this.el.parentNode) {
          this.el.remove()
        }
      }, 400)
    }
  },
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
      // Regular compose mode only
      this.setupToolbar('#html-editor', 'preview-panel', 'preview-content')
      this.setupPreview('#html-editor', 'preview-panel', 'preview-content')
    },
    
    setupToolbar(targetSelector, previewPanelId, previewContentId) {
      // Find the toolbar that's a sibling of the target textarea
      const textarea = document.querySelector(targetSelector)
      if (!textarea) return
      
      // Look for toolbar in the parent form control div
      const formControl = textarea.closest('.form-control')
      if (!formControl) return
      
      const toolbar = formControl.querySelector('.flex.flex-wrap')
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
        
        if (button.dataset.format) {
          this.insertFormatInTarget(button.dataset.format, this.el)
        } else if (button.dataset.action === 'preview') {
          this.toggleReplyPreview(this.el)
        }
      })
    },
    
    setupReplyPreview() {
      // Auto-update preview if it's visible for reply mode
      this.el.addEventListener('input', () => {
        const previewPanel = document.getElementById('reply-preview-panel')
        const previewContent = document.getElementById('reply-preview-content')
        if (previewPanel && !previewPanel.classList.contains('hidden')) {
          const html = this.markdownToHtml(this.el.value)
          previewContent.innerHTML = html
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
  },
  ReplyMarkdownEditor: {
    mounted() {
      console.log("ReplyMarkdownEditor mounted on:", this.el)
      // Focus on the textarea when mounted (FocusOnMount functionality)
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
      
      // Setup markdown toolbar functionality
      this.setupReplyToolbars()
      this.setupReplyPreview()
    },
    
    setupReplyToolbars() {
      // Setup toolbar for reply/forward mode
      // Look for toolbar in the parent form control div
      const formControl = this.el.closest('.form-control')
      if (!formControl) {
        console.log("No form control found for reply editor!")
        return
      }
      
      const toolbar = formControl.querySelector('.flex.flex-wrap')
      if (!toolbar) {
        console.log("No toolbar found for reply editor!")
        return
      }
      
      console.log("Setting up event listener for reply toolbar")
      toolbar.addEventListener('click', (e) => {
        console.log("Toolbar clicked!", e.target)
        const button = e.target.closest('[data-format], [data-action]')
        if (!button) {
          console.log("No button found")
          return
        }
        
        console.log("Button found:", button, "format:", button.dataset.format)
        e.preventDefault()
        
        if (button.dataset.format) {
          console.log("Inserting format:", button.dataset.format)
          this.insertFormatInTarget(button.dataset.format, this.el)
        } else if (button.dataset.action === 'preview') {
          console.log("Toggling preview")
          this.toggleReplyPreview(this.el)
        }
      })
    },
    
    setupReplyPreview() {
      // Auto-update preview if it's visible for reply mode
      this.el.addEventListener('input', () => {
        const previewPanel = document.getElementById('reply-preview-panel')
        const previewContent = document.getElementById('reply-preview-content')
        if (previewPanel && !previewPanel.classList.contains('hidden')) {
          const html = this.markdownToHtml(this.el.value)
          previewContent.innerHTML = html
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

// Make markdown functions globally available
window.insertMarkdownFormat = insertMarkdownFormat
window.toggleMarkdownPreview = toggleMarkdownPreview
window.markdownToHtml = markdownToHtml

// Initialize homepage effects
document.addEventListener('DOMContentLoaded', () => {
  // Initialize generative art and digital effects for homepage
  initGenerativeArt()
  initDigitalEffects()
})