/**
 * Image Cropper Component
 * Allows users to crop avatar images to fit within size/dimension limits
 */

export class ImageCropper {
  constructor(options = {}) {
    this.maxWidth = options.maxWidth || 2048;
    this.maxHeight = options.maxHeight || 2048;
    this.maxFileSize = options.maxFileSize || 5 * 1024 * 1024; // 5MB
    this.quality = options.quality || 0.8;
    this.cropSize = Math.min(this.maxWidth, this.maxHeight); // Square crop
    
    this.canvas = null;
    this.ctx = null;
    this.img = null;
    this.isDragging = false;
    this.startX = 0;
    this.startY = 0;
    this.cropX = 0;
    this.cropY = 0;
    this.scale = 1;
  }

  init() {
    this.createCropperElements();
    this.bindEvents();
  }

  createCropperElements() {
    // Create modal container
    this.modal = document.createElement('div');
    this.modal.className = 'image-cropper-modal';
    this.modal.innerHTML = `
      <div class="image-cropper-backdrop"></div>
      <div class="image-cropper-container">
        <div class="image-cropper-header">
          <h3>Crop Your Avatar</h3>
          <button type="button" class="image-cropper-close" aria-label="Close">&times;</button>
        </div>
        <div class="image-cropper-body">
          <div class="image-cropper-main-content">
            <div class="image-cropper-canvas-container">
              <canvas class="image-cropper-canvas"></canvas>
              <div class="image-cropper-overlay">
                <div class="image-cropper-crop-area"></div>
              </div>
            </div>
            <div class="image-cropper-preview-container">
              <h4>Preview</h4>
              <div class="image-cropper-preview-wrapper">
                <canvas class="image-cropper-preview"></canvas>
              </div>
              <div class="image-cropper-preview-info">
                <small>This is how your avatar will look</small>
              </div>
            </div>
          </div>
          <div class="image-cropper-controls">
            <div class="image-cropper-zoom">
              <label>Zoom:</label>
              <input type="range" class="image-cropper-zoom-slider" min="0.5" max="3" step="0.1" value="1">
            </div>
            <div class="image-cropper-info">
              <small>Drag to move the image. Use zoom to fit your image perfectly.</small>
            </div>
          </div>
        </div>
        <div class="image-cropper-footer">
          <button type="button" class="btn btn-ghost image-cropper-cancel">Cancel</button>
          <button type="button" class="btn btn-outline image-cropper-skip">Use Original</button>
          <button type="button" class="btn btn-primary image-cropper-save">Crop & Save</button>
        </div>
      </div>
    `;
    
    document.body.appendChild(this.modal);
    
    // Get references
    this.canvas = this.modal.querySelector('.image-cropper-canvas');
    this.ctx = this.canvas.getContext('2d');
    this.previewCanvas = this.modal.querySelector('.image-cropper-preview');
    this.previewCtx = this.previewCanvas.getContext('2d');
    this.overlay = this.modal.querySelector('.image-cropper-overlay');
    this.cropArea = this.modal.querySelector('.image-cropper-crop-area');
    this.zoomSlider = this.modal.querySelector('.image-cropper-zoom-slider');
    
    // Set canvas size
    this.canvas.width = 400;
    this.canvas.height = 400;
    
    // Set preview canvas size (smaller, circular)
    this.previewCanvas.width = 150;
    this.previewCanvas.height = 150;
    
    // Style the crop area - move it up to be fully visible
    this.cropArea.style.width = '300px';
    this.cropArea.style.height = '300px';
    this.cropArea.style.left = '50px';
    this.cropArea.style.top = '10px'; // Moved up to 10px for maximum clearance
  }

  bindEvents() {
    // Close events
    this.modal.querySelector('.image-cropper-close').addEventListener('click', () => this.close());
    this.modal.querySelector('.image-cropper-cancel').addEventListener('click', () => this.close());
    this.modal.querySelector('.image-cropper-backdrop').addEventListener('click', () => this.close());
    
    // Save events
    this.modal.querySelector('.image-cropper-save').addEventListener('click', () => this.save());
    this.modal.querySelector('.image-cropper-skip').addEventListener('click', () => this.useOriginal());
    
    // Canvas events for dragging
    this.canvas.addEventListener('mousedown', (e) => this.startDrag(e));
    this.canvas.addEventListener('mousemove', (e) => this.drag(e));
    this.canvas.addEventListener('mouseup', () => this.endDrag());
    this.canvas.addEventListener('mouseleave', () => this.endDrag());
    
    // Touch events for mobile
    this.canvas.addEventListener('touchstart', (e) => this.startDrag(e.touches[0]));
    this.canvas.addEventListener('touchmove', (e) => {
      e.preventDefault();
      this.drag(e.touches[0]);
    });
    this.canvas.addEventListener('touchend', () => this.endDrag());
    
    // Zoom event
    this.zoomSlider.addEventListener('input', (e) => {
      this.scale = parseFloat(e.target.value);
      this.redraw();
    });
  }

  open(file, onSave) {
    this.onSave = onSave;
    this.originalFile = file; // Store original file for "Use Original" option
    
    // Validate file
    if (!this.validateFile(file)) {
      return;
    }
    
    // Load image
    this.loadImage(file).then(() => {
      this.modal.style.display = 'block';
      this.centerImage();
      this.redraw();
    }).catch(error => {
      alert('Failed to load image: ' + error.message);
    });
  }

  close() {
    this.modal.style.display = 'none';
    this.img = null;
    this.cropX = 0;
    this.cropY = 0;
    this.scale = 1;
    this.zoomSlider.value = 1;
  }

  validateFile(file) {
    if (!file.type.startsWith('image/')) {
      alert('Please select an image file.');
      return false;
    }
    
    if (file.size > this.maxFileSize) {
      const maxMB = this.maxFileSize / (1024 * 1024);
      alert(`File size must be less than ${maxMB}MB. Your file is ${(file.size / (1024 * 1024)).toFixed(2)}MB.`);
      return false;
    }
    
    return true;
  }

  loadImage(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = (e) => {
        this.img = new Image();
        this.img.onload = () => {
          resolve();
        };
        this.img.onerror = () => {
          reject(new Error('Failed to load image'));
        };
        this.img.src = e.target.result;
      };
      reader.onerror = () => {
        reject(new Error('Failed to read file'));
      };
      reader.readAsDataURL(file);
    });
  }

  centerImage() {
    if (!this.img) return;
    
    // Calculate scale to fit image in canvas while maintaining aspect ratio
    const scaleX = this.canvas.width / this.img.width;
    const scaleY = this.canvas.height / this.img.height;
    this.scale = Math.min(scaleX, scaleY);
    
    // Center the image
    const scaledWidth = this.img.width * this.scale;
    const scaledHeight = this.img.height * this.scale;
    this.cropX = (this.canvas.width - scaledWidth) / 2;
    this.cropY = (this.canvas.height - scaledHeight) / 2;
    
    this.zoomSlider.value = this.scale;
  }

  redraw() {
    if (!this.img) return;
    
    // Clear canvas
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    
    // Draw image
    const scaledWidth = this.img.width * this.scale;
    const scaledHeight = this.img.height * this.scale;
    
    this.ctx.drawImage(
      this.img,
      this.cropX,
      this.cropY,
      scaledWidth,
      scaledHeight
    );
    
    // Update preview
    this.updatePreview();
  }

  updatePreview() {
    if (!this.img) return;
    
    // Clear preview canvas
    this.previewCtx.clearRect(0, 0, this.previewCanvas.width, this.previewCanvas.height);
    
    // Calculate crop area in original image coordinates
    const cropAreaX = 0; // Fixed position on canvas
    const cropAreaY = 0; // Moved up 25px to match visual position
    const cropAreaSize = 300; // Fixed size on canvas
    
    // Convert canvas coordinates to image coordinates
    const imageX = (cropAreaX - this.cropX) / this.scale;
    const imageY = (cropAreaY - this.cropY) / this.scale;
    const imageSize = cropAreaSize / this.scale;
    
    // Save context to restore later
    this.previewCtx.save();
    
    // Create circular clipping path
    const centerX = this.previewCanvas.width / 2;
    const centerY = this.previewCanvas.height / 2;
    const radius = Math.min(centerX, centerY) - 2; // Small margin
    
    this.previewCtx.beginPath();
    this.previewCtx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
    this.previewCtx.clip();
    
    // Draw cropped portion to preview canvas
    try {
      this.previewCtx.drawImage(
        this.img,
        imageX,
        imageY,
        imageSize,
        imageSize,
        2, // Small margin
        2, // Small margin
        this.previewCanvas.width - 4, // Account for margin
        this.previewCanvas.height - 4  // Account for margin
      );
    } catch (error) {
      console.log('Preview update error (normal during adjustment):', error.message);
    }
    
    // Restore context
    this.previewCtx.restore();
    
    // Draw circular border
    this.previewCtx.strokeStyle = '#3b82f6';
    this.previewCtx.lineWidth = 2;
    this.previewCtx.beginPath();
    this.previewCtx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
    this.previewCtx.stroke();
  }

  startDrag(e) {
    this.isDragging = true;
    const rect = this.canvas.getBoundingClientRect();
    this.startX = (e.clientX || e.pageX) - rect.left - this.cropX;
    this.startY = (e.clientY || e.pageY) - rect.top - this.cropY;
  }

  drag(e) {
    if (!this.isDragging) return;
    
    const rect = this.canvas.getBoundingClientRect();
    this.cropX = (e.clientX || e.pageX) - rect.left - this.startX;
    this.cropY = (e.clientY || e.pageY) - rect.top - this.startY;
    
    this.redraw();
  }

  endDrag() {
    this.isDragging = false;
  }

  save() {
    console.log('Save button clicked');
    if (!this.img) {
      console.error('No image loaded');
      return;
    }
    
    console.log('Creating output canvas...');
    // Create output canvas for cropped image
    const outputCanvas = document.createElement('canvas');
    const outputCtx = outputCanvas.getContext('2d');
    
    // Set output size (square crop)
    const outputSize = Math.min(this.cropSize, 1024); // Max 1024px for reasonable file size
    outputCanvas.width = outputSize;
    outputCanvas.height = outputSize;
    
    console.log(`Output canvas size: ${outputSize}x${outputSize}`);
    
    // Calculate crop area in original image coordinates
    const cropAreaX = 0; // Fixed position on canvas
    const cropAreaY = 0; // Moved up 25px to match visual position
    const cropAreaSize = 300; // Fixed size on canvas
    
    // Convert canvas coordinates to image coordinates
    const imageX = (cropAreaX - this.cropX) / this.scale;
    const imageY = (cropAreaY - this.cropY) / this.scale;
    const imageSize = cropAreaSize / this.scale;
    
    console.log(`Crop coordinates: imageX=${imageX}, imageY=${imageY}, imageSize=${imageSize}`);
    console.log(`Canvas position: cropX=${this.cropX}, cropY=${this.cropY}, scale=${this.scale}`);
    
    // Draw cropped portion to output canvas
    try {
      outputCtx.drawImage(
        this.img,
        imageX,
        imageY,
        imageSize,
        imageSize,
        0,
        0,
        outputSize,
        outputSize
      );
      console.log('Successfully drew image to output canvas');
    } catch (error) {
      console.error('Error drawing image:', error);
      alert('Failed to crop image: ' + error.message);
      return;
    }
    
    // Convert to blob
    console.log('Converting canvas to blob...');
    outputCanvas.toBlob((blob) => {
      console.log('Blob created:', blob);
      if (blob) {
        console.log(`Blob size: ${blob.size} bytes, type: ${blob.type}`);
        
        // Create a File object from the blob
        const fileName = `cropped-avatar-${Date.now()}.jpg`;
        const croppedFile = new File([blob], fileName, { type: 'image/jpeg' });
        
        console.log('Created file:', croppedFile);
        console.log('Calling onSave callback...');
        
        // Call the save callback
        if (this.onSave) {
          this.onSave(croppedFile);
        } else {
          console.error('No onSave callback defined');
        }
        
        this.close();
      } else {
        console.error('Failed to create blob');
        alert('Failed to create cropped image');
      }
    }, 'image/jpeg', this.quality);
  }

  useOriginal() {
    console.log('Use Original button clicked');
    if (!this.originalFile) {
      console.error('No original file available');
      return;
    }
    
    console.log('Using original file:', this.originalFile);
    
    // Call the save callback with the original file
    if (this.onSave) {
      this.onSave(this.originalFile);
    } else {
      console.error('No onSave callback defined');
    }
    
    this.close();
  }
}

// Initialize image cropper for avatar uploads
export function initImageCropper() {
  console.log('Initializing image cropper...');
  
  const avatarInput = document.querySelector('input[type="file"][name="user[avatar]"]');
  if (!avatarInput) {
    console.log('No avatar input found, cropper not initialized');
    return;
  }
  
  console.log('Found avatar input:', avatarInput);
  
  const cropper = new ImageCropper({
    maxWidth: 2048,
    maxHeight: 2048,
    maxFileSize: 5 * 1024 * 1024, // 5MB
    quality: 0.8
  });
  
  cropper.init();
  console.log('Image cropper initialized');
  
  // Track if we're setting a cropped file to prevent loops
  let settingCroppedFile = false;
  
  // Replace input change handler
  avatarInput.addEventListener('change', (e) => {
    console.log('Avatar input changed, files:', e.target.files);
    const file = e.target.files[0];
    if (!file) {
      console.log('No file selected');
      return;
    }
    
    // Skip processing if this is a cropped file we just set
    if (settingCroppedFile) {
      console.log('Skipping cropper - this is a cropped file we just set');
      settingCroppedFile = false;
      return;
    }
    
    console.log('Selected file:', file);
    console.log('File size:', file.size, 'bytes');
    console.log('File type:', file.type);
    
    // Always open cropper for avatar images to ensure proper sizing/cropping
    console.log('Opening cropper for avatar image...');
    
    // Open cropper
    cropper.open(file, (croppedFile) => {
      console.log('Cropper onSave callback called with:', croppedFile);
      
      try {
        // Set flag to prevent loop
        settingCroppedFile = true;
        
        // Create new FileList with cropped file
        const dataTransfer = new DataTransfer();
        dataTransfer.items.add(croppedFile);
        avatarInput.files = dataTransfer.files;
        
        console.log('Updated input files:', avatarInput.files);
        console.log('Cropped file is ready for form submission');
        
        // Update the avatar preview image immediately
        updateAvatarPreview(croppedFile);
        
        // Show success message
        const successMsg = document.createElement('div');
        successMsg.className = 'alert alert-success mt-2';
        successMsg.innerHTML = `
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span>Avatar image ready! Click Save to upload.</span>
        `;
        
        // Add success message near the file input
        const avatarContainer = avatarInput.closest('.form-control');
        if (avatarContainer) {
          // Remove any existing success messages
          const existingMsg = avatarContainer.querySelector('.alert-success');
          if (existingMsg) existingMsg.remove();
          
          avatarContainer.appendChild(successMsg);
          
          // Remove success message after 5 seconds
          setTimeout(() => {
            if (successMsg.parentNode) {
              successMsg.remove();
            }
          }, 5000);
        }
        
      } catch (error) {
        settingCroppedFile = false;
        console.error('Error updating file input:', error);
        alert('Error updating file input: ' + error.message);
      }
    });
    
    // Clear the input to allow re-selecting the same file
    e.target.value = '';
  });
  
  console.log('Event listener added to avatar input');
  
  // Function to update the avatar preview in the settings page
  function updateAvatarPreview(file) {
    console.log('Updating avatar preview with:', file);
    
    // Find the avatar preview image in the settings page
    const avatarImg = document.querySelector('.avatar img[alt="Current avatar"]');
    const avatarPlaceholder = document.querySelector('.avatar .bg-primary');
    
    if (file && (avatarImg || avatarPlaceholder)) {
      // Create a URL for the file to display it
      const imageUrl = URL.createObjectURL(file);
      console.log('Created object URL:', imageUrl);
      
      if (avatarImg) {
        // Update existing image
        avatarImg.src = imageUrl;
        console.log('Updated existing avatar image');
      } else if (avatarPlaceholder) {
        // Replace placeholder with image
        const avatarContainer = avatarPlaceholder.parentElement;
        avatarContainer.innerHTML = `<img src="${imageUrl}" alt="Current avatar" />`;
        console.log('Replaced placeholder with new avatar image');
      }
      
      // Clean up the object URL after a delay to avoid memory leaks
      setTimeout(() => {
        URL.revokeObjectURL(imageUrl);
        console.log('Revoked object URL');
      }, 10000); // Keep it for 10 seconds to ensure it loads
    } else {
      console.log('No avatar preview found or no file provided');
    }
  }
  
  // Make the function available to the cropper
  cropper.updateAvatarPreview = updateAvatarPreview;
}