const installer = document.querySelector('.installer');
const replay = document.querySelector('#replay');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

function playInstallation() {
  installer.classList.remove('play');
  if (reducedMotion.matches) return;
  const items = installer.querySelectorAll('.install-item');
  const distance = items[1].getBoundingClientRect().left - items[0].getBoundingClientRect().left;
  installer.style.setProperty('--drag-distance', `${distance}px`);
  requestAnimationFrame(() => requestAnimationFrame(() => installer.classList.add('play')));
}
replay.addEventListener('click', playInstallation);
if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver(entries => {
    if (entries.some(entry => entry.isIntersecting)) {
      playInstallation();
      observer.disconnect();
    }
  }, { threshold: 0.5 });
  observer.observe(installer);
}
// Packaging supplies this metadata alongside the actual installers.
fetch('downloads/release.json').then(response => {
  if (!response.ok) throw new Error('Release metadata unavailable');
  return response.json();
}).then(release => {
  if (/^\d+\.\d+\.\d+$/.test(release.version)) {
    document.querySelectorAll('[data-version]').forEach(node => {
      node.textContent = `Version ${release.version}`;
    });
  }
}).catch(() => { /* The source page still works without optional version metadata. */ });
