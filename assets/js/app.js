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

// Global function to show keyboard shortcuts (called from buttons)
window.showKeyboardShortcuts = function() {
  const modal = document.createElement('div')
  modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50'
  modal.innerHTML = `
    <div class="bg-base-100 rounded-lg shadow-xl p-6 max-w-2xl w-full mx-4 max-h-96 overflow-y-auto" onclick="event.stopPropagation()">
      <div class="flex justify-between items-center mb-6">
        <h2 class="text-2xl font-bold">Keyboard Shortcuts</h2>
        <button class="btn btn-ghost btn-sm" onclick="this.closest('.fixed').remove()">✕</button>
      </div>
      
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <h3 class="font-semibold mb-3">Navigation</h3>
          <div class="space-y-2 text-sm">
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">c</kbd>
              <span>Compose</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">g</kbd>
              <span>Go to menu</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">/</kbd>
              <span>Search</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">j</kbd>
              <span>Next message</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">k</kbd>
              <span>Previous message</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">Enter</kbd>
              <span>Open message</span>
            </div>
          </div>
        </div>
        
        <div>
          <h3 class="font-semibold mb-3">Actions</h3>
          <div class="space-y-2 text-sm">
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">e</kbd>
              <span>Archive</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">r</kbd>
              <span>Reply</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">f</kbd>
              <span>Forward</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">#</kbd>
              <span>Delete</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">!</kbd>
              <span>Mark as spam</span>
            </div>
            <div class="flex justify-between">
              <kbd class="kbd kbd-sm">Shift + /</kbd>
              <span>Show this help (?)</span>
            </div>
          </div>
        </div>
      </div>
      
      <div class="mt-6 p-4 bg-base-200 rounded-lg">
        <h4 class="font-semibold mb-2">Go to shortcuts (press 'g' then):</h4>
        <div class="grid grid-cols-2 gap-2 text-sm">
          <div><kbd class="kbd kbd-xs">i</kbd> Inbox</div>
          <div><kbd class="kbd kbd-xs">s</kbd> Sent</div>
          <div><kbd class="kbd kbd-xs">t</kbd> Search</div>
          <div><kbd class="kbd kbd-xs">a</kbd> Archive</div>
          <div><kbd class="kbd kbd-xs">p</kbd> Spam</div>
        </div>
      </div>
    </div>
  `
  
  // Close modal when clicking outside the content area
  modal.addEventListener('click', () => {
    modal.remove()
  })
  
  document.body.appendChild(modal)
}

// Define hooks for custom JavaScript behaviors
const Hooks = {
  FlashMessage: {
    mounted() {
      // Prevent multiple mounts on the same element
      if (this.el.dataset.flashMounted) return
      this.el.dataset.flashMounted = 'true'
      
      // Simple fade in
      this.el.style.opacity = '0'
      this.fadeInTimeout = setTimeout(() => {
        if (this.el) this.el.style.opacity = '1'
      }, 50)
      
      // Find and start progress bar animation
      this.progressBar = this.el.querySelector('.flash-progress')
      if (this.progressBar) {
        this.progressTimeout = setTimeout(() => {
          if (this.progressBar) this.progressBar.classList.add('animate')
        }, 200)
      }
      
      // Set up auto-hide timer
      this.autoHideTimer = setTimeout(() => {
        this.hide()
      }, 5000)
      
      // Handle click to dismiss
      this.clickHandler = () => this.hide()
      this.el.addEventListener('click', this.clickHandler)
    },
    
    destroyed() {
      // Clear all timeouts
      if (this.autoHideTimer) clearTimeout(this.autoHideTimer)
      if (this.fadeInTimeout) clearTimeout(this.fadeInTimeout)
      if (this.progressTimeout) clearTimeout(this.progressTimeout)
      if (this.fadeOutTimeout) clearTimeout(this.fadeOutTimeout)
      
      // Remove event listener
      if (this.clickHandler) {
        this.el.removeEventListener('click', this.clickHandler)
      }
    },
    
    hide() {
      if (this.autoHideTimer) {
        clearTimeout(this.autoHideTimer)
        this.autoHideTimer = null
      }
      
      // Prevent double hide
      if (this.el.dataset.hiding) return
      this.el.dataset.hiding = 'true'
      
      // Simple fade out
      this.el.style.opacity = '0'
      
      this.fadeOutTimeout = setTimeout(() => {
        if (this.el && this.el.parentNode) {
          this.el.remove()
        }
      }, 200)
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
  },
  FileDownloader: {
    mounted() {
      this.handleEvent("download_file", ({filename, data, content_type}) => {
        try {
          // Decode base64 data
          const binaryString = atob(data)
          const bytes = new Uint8Array(binaryString.length)
          for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i)
          }
          
          // Create blob and download
          const blob = new Blob([bytes], { type: content_type })
          const url = URL.createObjectURL(blob)
          
          const link = document.createElement('a')
          link.href = url
          link.download = filename
          link.style.display = 'none'
          
          document.body.appendChild(link)
          link.click()
          document.body.removeChild(link)
          
          // Clean up
          URL.revokeObjectURL(url)
        } catch (error) {
          console.error('Failed to download file:', error)
          // Show error to user via flash message
          this.pushEvent("download_error", {message: "Failed to download attachment"})
        }
      })
    }
  },
  KeyboardShortcuts: {
    mounted() {
      console.log("Keyboard shortcuts enabled")
      this.setupKeyboardShortcuts()
    },
    
    setupKeyboardShortcuts() {
      // Track selected message for keyboard navigation
      this.selectedMessageIndex = -1
      this.messages = []
      
      // Update message list when DOM changes
      this.updateMessageList()
      
      document.addEventListener('keydown', (e) => {
        // Don't interfere when typing in inputs, textareas, or contenteditable elements
        if (e.target.tagName === 'INPUT' || 
            e.target.tagName === 'TEXTAREA' || 
            e.target.contentEditable === 'true' ||
            e.target.closest('.dropdown.dropdown-open')) {
          return
        }
        
        // Handle shortcuts
        this.handleKeyboardShortcut(e)
      })
      
      // Update message list when new messages are added
      const observer = new MutationObserver(() => {
        this.updateMessageList()
      })
      
      observer.observe(this.el, {
        childList: true,
        subtree: true
      })
      
      this.observer = observer
    },
    
    destroyed() {
      if (this.observer) {
        this.observer.disconnect()
      }
    },
    
    updateMessageList() {
      this.messages = Array.from(this.el.querySelectorAll('[id^="message-"]'))
      if (this.selectedMessageIndex >= this.messages.length) {
        this.selectedMessageIndex = this.messages.length - 1
      }
    },
    
    handleKeyboardShortcut(e) {
      const key = e.key.toLowerCase()
      const ctrl = e.ctrlKey || e.metaKey
      
      // Gmail-style shortcuts
      switch (key) {
        case 'c':
          if (!ctrl) {
            e.preventDefault()
            this.navigateToCompose()
          }
          break
          
        case 'g':
          if (!ctrl) {
            e.preventDefault()
            this.showGotoMenu()
          }
          break
          
        case '/':
          e.preventDefault()
          this.focusSearch()
          break
          
        case '?':
          e.preventDefault()
          this.showShortcutsHelp()
          break
          
        case 'j':
          if (!ctrl) {
            e.preventDefault()
            this.selectNextMessage()
          }
          break
          
        case 'k':
          if (!ctrl) {
            e.preventDefault()
            this.selectPrevMessage()
          }
          break
          
        case 'enter':
          if (this.selectedMessageIndex >= 0) {
            e.preventDefault()
            this.openSelectedMessage()
          }
          break
          
        case 'e':
          if (!ctrl && this.selectedMessageIndex >= 0) {
            e.preventDefault()
            this.archiveSelectedMessage()
          }
          break
          
        case 'r':
          if (!ctrl && this.selectedMessageIndex >= 0) {
            e.preventDefault()
            this.replyToSelectedMessage()
          }
          break
          
        case 'f':
          if (!ctrl && this.selectedMessageIndex >= 0) {
            e.preventDefault()
            this.forwardSelectedMessage()
          }
          break
          
        case '#':
          if (this.selectedMessageIndex >= 0) {
            e.preventDefault()
            this.deleteSelectedMessage()
          }
          break
          
        case '!':
          if (this.selectedMessageIndex >= 0) {
            e.preventDefault()
            this.markSpamSelectedMessage()
          }
          break
          
      }
    },
    
    showGotoMenu() {
      // Show a temporary goto menu
      const menu = document.createElement('div')
      menu.className = 'fixed top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 bg-base-100 border border-base-300 rounded-lg shadow-xl p-6 z-50'
      menu.innerHTML = `
        <h3 class="text-lg font-bold mb-4">Go to...</h3>
        <div class="space-y-2">
          <button class="btn btn-ghost btn-sm w-full justify-start" data-goto="inbox">
            <span class="font-mono mr-2">gi</span> Inbox
          </button>
          <button class="btn btn-ghost btn-sm w-full justify-start" data-goto="sent">
            <span class="font-mono mr-2">gs</span> Sent
          </button>
          <button class="btn btn-ghost btn-sm w-full justify-start" data-goto="search">
            <span class="font-mono mr-2">gt</span> Search
          </button>
          <button class="btn btn-ghost btn-sm w-full justify-start" data-goto="archive">
            <span class="font-mono mr-2">ga</span> Archive
          </button>
          <button class="btn btn-ghost btn-sm w-full justify-start" data-goto="spam">
            <span class="font-mono mr-2">gp</span> Spam
          </button>
        </div>
        <div class="text-xs text-base-content/60 mt-4">Press Escape to close</div>
      `
      
      document.body.appendChild(menu)
      
      // Handle goto navigation
      menu.addEventListener('click', (e) => {
        const button = e.target.closest('[data-goto]')
        if (button) {
          const destination = button.dataset.goto
          this.navigateTo(destination)
          document.body.removeChild(menu)
        }
      })
      
      // Handle keyboard navigation in goto menu
      const handleGotoKey = (e) => {
        if (e.key === 'Escape') {
          document.body.removeChild(menu)
          document.removeEventListener('keydown', handleGotoKey)
        } else if (e.key === 'i') {
          this.navigateTo('inbox')
          document.body.removeChild(menu)
          document.removeEventListener('keydown', handleGotoKey)
        } else if (e.key === 's') {
          this.navigateTo('sent')
          document.body.removeChild(menu)
          document.removeEventListener('keydown', handleGotoKey)
        } else if (e.key === 't') {
          this.navigateTo('search')
          document.body.removeChild(menu)
          document.removeEventListener('keydown', handleGotoKey)
        } else if (e.key === 'a') {
          this.navigateTo('archive')
          document.body.removeChild(menu)
          document.removeEventListener('keydown', handleGotoKey)
        } else if (e.key === 'p') {
          this.navigateTo('spam')
          document.body.removeChild(menu)
          document.removeEventListener('keydown', handleGotoKey)
        }
      }
      
      document.addEventListener('keydown', handleGotoKey)
      
      // Auto-close after 5 seconds
      setTimeout(() => {
        if (menu.parentNode) {
          document.body.removeChild(menu)
          document.removeEventListener('keydown', handleGotoKey)
        }
      }, 5000)
    },
    
    navigateTo(destination) {
      const routes = {
        inbox: '/email/inbox',
        sent: '/email/sent',
        search: '/email/search',
        archive: '/email/archive',
        spam: '/email/spam'
      }
      
      if (routes[destination]) {
        window.location.href = routes[destination]
      }
    },
    
    navigateToCompose() {
      window.location.href = '/email/compose'
    },
    
    focusSearch() {
      // Try to focus search input if on search page
      const searchInput = document.querySelector('input[name="search[query]"]')
      if (searchInput) {
        searchInput.focus()
      } else {
        // Navigate to search page
        window.location.href = '/email/search'
      }
    },
    
    selectNextMessage() {
      if (this.messages.length === 0) return
      
      // Clear previous selection
      this.clearMessageSelection()
      
      this.selectedMessageIndex = Math.min(this.selectedMessageIndex + 1, this.messages.length - 1)
      this.highlightSelectedMessage()
    },
    
    selectPrevMessage() {
      if (this.messages.length === 0) return
      
      // Clear previous selection
      this.clearMessageSelection()
      
      this.selectedMessageIndex = Math.max(this.selectedMessageIndex - 1, 0)
      this.highlightSelectedMessage()
    },
    
    clearMessageSelection() {
      this.messages.forEach(msg => {
        msg.classList.remove('ring-2', 'ring-primary', 'ring-offset-2')
      })
    },
    
    highlightSelectedMessage() {
      if (this.selectedMessageIndex >= 0 && this.selectedMessageIndex < this.messages.length) {
        const selectedMsg = this.messages[this.selectedMessageIndex]
        selectedMsg.classList.add('ring-2', 'ring-primary', 'ring-offset-2')
        selectedMsg.scrollIntoView({ behavior: 'smooth', block: 'center' })
      }
    },
    
    openSelectedMessage() {
      if (this.selectedMessageIndex >= 0 && this.selectedMessageIndex < this.messages.length) {
        const selectedMsg = this.messages[this.selectedMessageIndex]
        const link = selectedMsg.querySelector('a[href*="/email/view/"]')
        if (link) {
          link.click()
        }
      }
    },
    
    archiveSelectedMessage() {
      this.performActionOnSelected('archive')
    },
    
    replyToSelectedMessage() {
      this.performActionOnSelected('reply')
    },
    
    forwardSelectedMessage() {
      this.performActionOnSelected('forward')
    },
    
    deleteSelectedMessage() {
      this.performActionOnSelected('delete')
    },
    
    markSpamSelectedMessage() {
      this.performActionOnSelected('mark_spam')
    },
    
    performActionOnSelected(action) {
      if (this.selectedMessageIndex >= 0 && this.selectedMessageIndex < this.messages.length) {
        const selectedMsg = this.messages[this.selectedMessageIndex]
        const messageId = selectedMsg.id.replace('message-', '')
        
        if (action === 'delete') {
          // Find delete button
          const deleteBtn = selectedMsg.querySelector('[phx-click="delete"]')
          if (deleteBtn && confirm('Are you sure you want to delete this message?')) {
            deleteBtn.click()
          }
        } else {
          // Find quick action button
          const actionBtn = selectedMsg.querySelector(`[phx-value-action="${action}"]`)
          if (actionBtn) {
            actionBtn.click()
          }
        }
      }
    },
    
    
    showShortcutsHelp() {
      const modal = document.createElement('div')
      modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50'
      modal.innerHTML = `
        <div class="bg-base-100 rounded-lg shadow-xl p-6 max-w-2xl w-full mx-4 max-h-96 overflow-y-auto" onclick="event.stopPropagation()">
          <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold">Keyboard Shortcuts</h2>
            <button class="btn btn-ghost btn-sm" onclick="this.closest('.fixed').remove()">✕</button>
          </div>
          
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <h3 class="font-semibold mb-3">Navigation</h3>
              <div class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">c</kbd>
                  <span>Compose</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">g</kbd>
                  <span>Go to menu</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">/</kbd>
                  <span>Search</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">j</kbd>
                  <span>Next message</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">k</kbd>
                  <span>Previous message</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">Enter</kbd>
                  <span>Open message</span>
                </div>
              </div>
            </div>
            
            <div>
              <h3 class="font-semibold mb-3">Actions</h3>
              <div class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">e</kbd>
                  <span>Archive</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">r</kbd>
                  <span>Reply</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">f</kbd>
                  <span>Forward</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">#</kbd>
                  <span>Delete</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">!</kbd>
                  <span>Mark as spam</span>
                </div>
                <div class="flex justify-between">
                  <kbd class="kbd kbd-sm">Shift + /</kbd>
                  <span>Show this help (?)</span>
                </div>
              </div>
            </div>
          </div>
          
          <div class="mt-6 p-4 bg-base-200 rounded-lg">
            <h4 class="font-semibold mb-2">Go to shortcuts (press 'g' then):</h4>
            <div class="grid grid-cols-2 gap-2 text-sm">
              <div><kbd class="kbd kbd-xs">i</kbd> Inbox</div>
              <div><kbd class="kbd kbd-xs">s</kbd> Sent</div>
              <div><kbd class="kbd kbd-xs">t</kbd> Search</div>
              <div><kbd class="kbd kbd-xs">a</kbd> Archive</div>
              <div><kbd class="kbd kbd-xs">p</kbd> Spam</div>
            </div>
          </div>
        </div>
      `
      
      // Close modal when clicking outside the content area
      modal.addEventListener('click', () => {
        modal.remove()
      })
      
      document.body.appendChild(modal)
    }
  },
  IframeAutoResize: {
    mounted() {
      const iframe = this.el
      
      // Function to resize iframe based on content
      const resizeIframe = () => {
        try {
          // Reset height to allow shrinking
          iframe.style.height = 'auto'
          
          // Get the content document
          const contentDoc = iframe.contentWindow.document
          const contentBody = contentDoc.body
          
          // Ensure the iframe content has proper overflow handling
          contentBody.style.overflowX = 'auto'
          contentBody.style.overflowY = 'auto'
          contentBody.style.wordWrap = 'break-word'
          contentBody.style.wordBreak = 'break-word'
          contentBody.style.maxWidth = '100%'
          
          // Get the actual content height, accounting for scrollbars
          const contentHeight = Math.max(
            contentBody.scrollHeight,
            contentBody.offsetHeight,
            contentDoc.documentElement.scrollHeight,
            contentDoc.documentElement.offsetHeight
          )
          
          // Set minimum height of 400px, maximum of viewport height - 200px
          const maxHeight = window.innerHeight - 200
          const newHeight = Math.max(400, Math.min(contentHeight + 40, maxHeight))
          
          iframe.style.height = newHeight + 'px'
          
          // Ensure the iframe itself handles overflow properly
          iframe.style.overflowX = 'auto'
          iframe.style.overflowY = 'auto'
          
        } catch (e) {
          // Cross-origin or other errors, use default height
          console.log('Could not resize iframe:', e)
          iframe.style.height = '600px'
        }
      }
      
      // Resize on load
      iframe.addEventListener('load', resizeIframe)
      
      // Also try to resize after delays (for dynamic content)
      iframe.addEventListener('load', () => {
        setTimeout(resizeIframe, 100)
        setTimeout(resizeIframe, 500)
        setTimeout(resizeIframe, 1000) // Give more time for complex layouts
      })
      
      // Handle window resize events
      window.addEventListener('resize', resizeIframe)
      
      // Store the resize function for cleanup
      this.resizeFunction = resizeIframe
    },
    
    destroyed() {
      // Clean up event listener
      if (this.resizeFunction) {
        window.removeEventListener('resize', this.resizeFunction)
      }
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

// Handle checkbox updates for message selection
window.addEventListener("phx:update_checkboxes", (e) => {
  const { selected_ids, select_all } = e.detail
  
  // Update all message checkboxes and card backgrounds
  const checkboxes = document.querySelectorAll('[id^="message-checkbox-"]')
  checkboxes.forEach(checkbox => {
    const messageId = parseInt(checkbox.id.replace('message-checkbox-', ''))
    const isSelected = select_all || selected_ids.includes(messageId)
    
    // Update checkbox
    checkbox.checked = isSelected
    
    // Update card background
    const messageCard = document.getElementById(`message-${messageId}`)
    if (messageCard) {
      if (isSelected) {
        messageCard.classList.add('message-selected')
      } else {
        messageCard.classList.remove('message-selected')
      }
    }
  })
})

// Add keyboard shortcuts for message selection
document.addEventListener('keydown', (e) => {
  // Only handle shortcuts when not typing in an input
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return
  
  // Ctrl+A or Cmd+A - Select all messages on page
  if ((e.ctrlKey || e.metaKey) && e.key === 'a') {
    e.preventDefault()
    const selectAllBtn = document.querySelector('[phx-click="select_all_messages"]')
    if (selectAllBtn) selectAllBtn.click()
  }
  
  // Escape - Clear selection
  if (e.key === 'Escape') {
    const clearBtn = document.querySelector('[phx-click="deselect_all_messages"]')
    if (clearBtn) clearBtn.click()
  }
})

// Handle shift+click for message selection
document.addEventListener('click', (e) => {
  const messageCard = e.target.closest('[phx-click="toggle_message_selection_on_shift"]')
  if (messageCard && e.shiftKey) {
    e.preventDefault()
    e.stopPropagation()
    const messageId = messageCard.getAttribute('phx-value-message_id')
    const checkbox = document.getElementById(`message-checkbox-${messageId}`)
    if (checkbox) {
      checkbox.click()
    }
  }
  
  // Handle individual checkbox clicks for immediate visual feedback
  if (e.target.type === 'checkbox' && e.target.id.startsWith('message-checkbox-')) {
    const messageId = e.target.id.replace('message-checkbox-', '')
    const messageCard = document.getElementById(`message-${messageId}`)
    if (messageCard) {
      // Small delay to let LiveView update first
      setTimeout(() => {
        if (e.target.checked) {
          messageCard.classList.add('message-selected')
        } else {
          messageCard.classList.remove('message-selected')
        }
      }, 50)
    }
  }
})

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