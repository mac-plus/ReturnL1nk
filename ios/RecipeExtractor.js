(function() {
  function parseJSONLDScripts() {
    const scripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
    for (const script of scripts) {
      try {
        const json = JSON.parse(script.innerText.trim());
        const recipe = locateRecipe(json);
        if (recipe) {
          return recipe;
        }
      } catch (error) {
        // Ignore malformed JSON and continue scanning
      }
    }
    return null;
  }

  function locateRecipe(json) {
    if (!json) return null;

    // Direct recipe object
    if (isRecipe(json)) return json;

    // Graph array
    if (Array.isArray(json['@graph'])) {
      const match = json['@graph'].find(isRecipe);
      if (match) return match;
    }

    // Array of potential recipes
    if (Array.isArray(json)) {
      const match = json.find(isRecipe);
      if (match) return match;
    }

    return null;
  }

  function isRecipe(obj) {
    if (!obj || typeof obj !== 'object') return false;
    const type = obj['@type'];
    if (typeof type === 'string') {
      return type.toLowerCase().includes('recipe');
    }
    if (Array.isArray(type)) {
      return type.some(t => typeof t === 'string' && t.toLowerCase().includes('recipe'));
    }
    return false;
  }

  const recipe = parseJSONLDScripts();
  if (recipe) {
    const payload = JSON.stringify(recipe);
    // Notify the share extension
    const message = { recipe: payload };
    window.webkit.messageHandlers.recipeHandler.postMessage(message);
  } else {
    window.webkit.messageHandlers.recipeHandler.postMessage({ error: 'No recipe JSON-LD found' });
  }
})();
