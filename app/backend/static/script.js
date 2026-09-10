const toursEl = document.getElementById('tours');
const podInfoEl = document.getElementById('pod-info');

async function loadTours() {
  const res = await fetch('/api/tours');
  const tours = await res.json();
  toursEl.innerHTML = tours.map(t => `
    <div class="card">
      <div class="emoji">${t.emoji}</div>
      <h3>${t.name}</h3>
      <p>${t.description}</p>
      <div class="meta">
        <span>${t.days} day${t.days > 1 ? 's' : ''}</span>
        <span class="price">$${t.price_usd}</span>
      </div>
    </div>
  `).join('');
}

async function loadPodInfo() {
  const res = await fetch('/api/info');
  const data = await res.json();
  podInfoEl.innerHTML = Object.entries(data)
    .map(([key, value]) => `<dt>${key}</dt><dd>${value}</dd>`)
    .join('');
}

loadTours();
loadPodInfo();
// Poll periodically so browsing the page alone shows the Service spreading traffic across pods.
setInterval(loadPodInfo, 4000);
