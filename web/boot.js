// Runs before first paint: apply a saved Paper/Cyanotype choice so the page
// does not flash the other theme. Storage may be unavailable; that is fine.
(function () {
  try {
    var saved = JSON.parse(localStorage.getItem('single-track/v1') || '{}');
    if (saved.theme === 'light' || saved.theme === 'dark') {
      document.documentElement.setAttribute('data-theme', saved.theme);
    }
  } catch (e) {
    /* no saved theme */
  }
})();
