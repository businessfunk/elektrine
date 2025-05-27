// Generative art canvas for homepage
export function initGenerativeArt() {
  // Only run if we're on a page with the generative canvas
  const canvas = document.getElementById('generative-canvas');
  if (!canvas) return;
  
  const ctx = canvas.getContext('2d');
  
  // Set canvas dimensions
  function resizeCanvas() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
  }
  
  // Initial sizing
  resizeCanvas();
  
  // Handle window resize
  window.addEventListener('resize', resizeCanvas);
  
  // Node points for network visualization
  const nodes = [];
  const nodeCount = 50;
  const connectionDistance = 150;
  
  // Create nodes
  for (let i = 0; i < nodeCount; i++) {
    nodes.push({
      x: Math.random() * canvas.width,
      y: Math.random() * canvas.height,
      size: Math.random() * 2 + 1,
      speedX: (Math.random() - 0.5) * 0.3,
      speedY: (Math.random() - 0.5) * 0.3
    });
  }
  
  // Animation loop
  function draw() {
    // Clear canvas with semi-transparent background for trail effect
    ctx.fillStyle = 'rgba(15, 23, 42, 0.05)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    // Update and draw nodes
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      
      // Move nodes
      node.x += node.speedX;
      node.y += node.speedY;
      
      // Bounce off boundaries
      if (node.x < 0 || node.x > canvas.width) node.speedX *= -1;
      if (node.y < 0 || node.y > canvas.height) node.speedY *= -1;
      
      // Draw node with warm/cool color variation
      const colorChoice = Math.sin(Date.now() * 0.001 + i) > 0.7;
      ctx.beginPath();
      ctx.arc(node.x, node.y, node.size, 0, Math.PI * 2);
      ctx.fillStyle = colorChoice ? 'rgba(255, 165, 0, 0.4)' : 'rgba(34, 211, 238, 0.6)';
      ctx.fill();
      
      // Draw connections between nodes
      for (let j = i + 1; j < nodes.length; j++) {
        const otherNode = nodes[j];
        const dx = otherNode.x - node.x;
        const dy = otherNode.y - node.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        
        if (distance < connectionDistance) {
          // Opacity based on distance
          const opacity = 1 - (distance / connectionDistance);
          ctx.beginPath();
          ctx.moveTo(node.x, node.y);
          ctx.lineTo(otherNode.x, otherNode.y);
          const connectionColor = Math.sin(Date.now() * 0.0005 + i + j) > 0.8 ? 
            `rgba(255, 69, 0, ${opacity * 0.15})` : 
            `rgba(34, 211, 238, ${opacity * 0.2})`;
          ctx.strokeStyle = connectionColor;
          ctx.lineWidth = 0.5;
          ctx.stroke();
        }
      }
    }
    
    requestAnimationFrame(draw);
  }
  
  // Start animation
  draw();
}

// Digital text effects
export function initDigitalEffects() {
  // Add subtle pulse effect to main title
  const title = document.querySelector('.digital-text');
  if (!title) return;
  
  let pulseIntensity = 0;
  let increasing = true;
  
  setInterval(() => {
    if (increasing) {
      pulseIntensity += 0.05;
      if (pulseIntensity >= 1) increasing = false;
    } else {
      pulseIntensity -= 0.05;
      if (pulseIntensity <= 0) increasing = true;
    }
    
    title.style.textShadow = `0 0 ${5 + pulseIntensity * 8}px rgba(34, 211, 238, ${0.5 + pulseIntensity * 0.3}), 0 0 ${3 + pulseIntensity * 6}px rgba(255, 165, 0, ${0.3 + pulseIntensity * 0.2})`;
  }, 50);
  
  // Cursor blink effect
  const cursor = document.querySelector('.cursor-blink');
  if (cursor) {
    setInterval(() => {
      cursor.style.opacity = cursor.style.opacity === '0' ? '1' : '0';
    }, 500);
  }
}