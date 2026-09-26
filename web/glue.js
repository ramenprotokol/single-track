// Browser glue for the Elm app: flags, saved progress, theme, clipboard,
// reduced-motion and colour-scheme changes, scrolling the stage into view
// and pointer capture. No game logic lives here.
(function () {
  var KEY = 'single-track/v1';
  var motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  var dark = window.matchMedia('(prefers-color-scheme: dark)');

  var saved = '';
  try {
    saved = localStorage.getItem(KEY) || '';
  } catch (e) {
    saved = '';
  }
  // Refuse absurd stored values rather than parse them.
  if (saved.length > 20000) saved = '';

  var app = window.Elm.Main.init({
    flags: {
      width: window.innerWidth,
      height: window.innerHeight,
      reducedMotion: motion.matches,
      prefersDark: dark.matches,
      saved: saved
    }
  });

  app.ports.save.subscribe(function (value) {
    try {
      localStorage.setItem(KEY, value);
    } catch (e) {
      /* private mode or storage full: progress simply is not kept */
    }
  });

  app.ports.setTheme.subscribe(function (theme) {
    if (theme === 'light' || theme === 'dark') {
      document.documentElement.setAttribute('data-theme', theme);
    } else {
      document.documentElement.removeAttribute('data-theme');
    }
  });

  app.ports.copyLink.subscribe(function (fragment) {
    var url = location.origin + location.pathname + '#' + fragment;
    if (!navigator.clipboard || !window.isSecureContext) {
      app.ports.copied.send(false);
      return;
    }
    navigator.clipboard.writeText(url).then(
      function () { app.ports.copied.send(true); },
      function () { app.ports.copied.send(false); }
    );
  });

  var onMotion = function (e) { app.ports.motion.send(e.matches); };
  if (motion.addEventListener) motion.addEventListener('change', onMotion);

  // A theme left on "automatic" follows the system as it changes.
  var onScheme = function (e) { app.ports.scheme.send(e.matches); };
  if (dark.addEventListener) dark.addEventListener('change', onScheme);

  // Run brings the stage (run controls, chart and survey) fully into view,
  // after Elm has drawn the frame. Instant under reduced motion.
  app.ports.reveal.subscribe(function (id) {
    requestAnimationFrame(function () {
      var el = document.getElementById(id);
      if (!el) return;
      var box = el.getBoundingClientRect();
      if (box.top >= 0 && box.bottom <= window.innerHeight) return;
      el.scrollIntoView({ block: 'start', behavior: motion.matches ? 'auto' : 'smooth' });
    });
  });

  // Keep a drag going when the pointer leaves the chart: capture it on the
  // chart surface, which is where Elm listens for moves.
  document.addEventListener('pointerdown', function (e) {
    var target = e.target;
    if (!(target instanceof Element) || !target.closest('[data-grab]')) return;
    var surface = target.closest('[data-capture]');
    if (!surface) return;
    try {
      surface.setPointerCapture(e.pointerId);
    } catch (err) {
      /* capture is a nicety */
    }
  });
})();
