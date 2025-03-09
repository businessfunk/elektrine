// home.js - Interactive elements for the home page

// Wait for the DOM to be fully loaded
document.addEventListener("DOMContentLoaded", () => {
  // Set random CSS variables for background elements
  const root = document.documentElement;
  
  // Create 6 random values for positioning elements
  for (let i = 0; i < 6; i++) {
    root.style.setProperty(`--random-${i}`, Math.random().toFixed(2));
  }

  // Add random subtle animations to background elements
  const backgroundElements = document.querySelectorAll(".animate-pulse-subtle");
  if (backgroundElements.length > 0) {
    backgroundElements.forEach((element) => {
      // Random animation delay for each element
      const delay = Math.random() * 5;
      element.style.animationDelay = `${delay}s`;
    });
  }
  
  // Set up cyberpunk text effect
  const cyberpunkText = document.querySelector(".cyberpunk-text");
  if (cyberpunkText) {
    cyberpunkText.setAttribute("data-text", cyberpunkText.textContent);
  }
  
  // Enhanced glitch effect with natural randomness
  const glitchElement = document.querySelector(".cyberpunk-glitch");
  if (glitchElement) {
    // Initial random opacity
    glitchElement.style.opacity = (0.03 + Math.random() * 0.04).toFixed(2);
    
    // Create natural random glitch patterns
    const createGlitchPattern = () => {
      // Random timing for next glitch
      const nextGlitchDelay = 2000 + Math.random() * 5000;
      
      setTimeout(() => {
        // Random number of flickers (1-3)
        const flickerCount = Math.floor(Math.random() * 3) + 1;
        let flickersDone = 0;
        
        // Create a sequence of flickers
        const flicker = () => {
          // Increase opacity for glitch effect
          glitchElement.style.opacity = (0.1 + Math.random() * 0.15).toFixed(2);
          
          // Random duration for this flicker
          const flickerDuration = 50 + Math.random() * 150;
          
          // Reset after flicker
          setTimeout(() => {
            // Return to base opacity
            glitchElement.style.opacity = (0.03 + Math.random() * 0.04).toFixed(2);
            
            flickersDone++;
            
            // Continue flickering if we have more in this sequence
            if (flickersDone < flickerCount) {
              setTimeout(flicker, 50 + Math.random() * 100);
            } else {
              // Schedule next glitch pattern
              createGlitchPattern();
            }
          }, flickerDuration);
        };
        
        // Start the flicker sequence
        flicker();
      }, nextGlitchDelay);
    };
    
    // Start the first glitch pattern
    createGlitchPattern();
  }

  // Add random glitch effect
  setInterval(() => {
    const glitchElement = document.querySelector(".cyberpunk-glitch");
    if (glitchElement && Math.random() > 0.7) {
      glitchElement.style.opacity = "0.2";
      setTimeout(() => {
        glitchElement.style.opacity = "0.05";
      }, 100);
    }
  }, 3000);

  // Mouse interaction for hexagon patterns has been removed
}); 