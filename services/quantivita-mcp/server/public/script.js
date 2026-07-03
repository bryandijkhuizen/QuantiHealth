const form = document.querySelector('#login-form');
const accountInput = document.querySelector('#account-id');
const tokenInput = document.querySelector('#sync-token');
const stats = document.querySelector('#stats');
const csvLink = document.querySelector('#csv-link');
const loginStatus = document.querySelector('#login-status');
const appleLogin = document.querySelector('#apple-login');
const logoutButton = document.querySelector('#logout-button');
const authCard = document.querySelector('#auth-card');
const themeToggle = document.querySelector('#theme-toggle');
const progressaSyncButton = document.querySelector('#progressa-sync');
let currentSession = null;

const storedTheme = localStorage.getItem('quantivitaTheme');
if (storedTheme) document.documentElement.dataset.theme = storedTheme;

form.addEventListener('submit', (event) => {
  event.preventDefault();
  login(accountInput.value.trim(), tokenInput.value.trim());
});

logoutButton.addEventListener('click', async () => {
  localStorage.removeItem('quantivitaSession');
  await fetch('/api/logout', { method: 'POST' });
  location.reload();
});

themeToggle.addEventListener('click', () => {
  const current = document.documentElement.dataset.theme;
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  localStorage.setItem('quantivitaTheme', next);
});

progressaSyncButton.addEventListener('click', syncProgressaWorkouts);

bootstrap();

async function bootstrap() {
  const params = new URLSearchParams(location.search);
  if (params.get('error')) loginStatus.textContent = params.get('error');

  const config = await fetch('/api/auth/config').then((response) => response.json());
  appleLogin.hidden = !config.appleEnabled;
  if (!config.appleEnabled) {
    loginStatus.textContent = 'Apple dashboard login is not configured. Use developer token login.';
  }

  const session = await fetch('/api/me/session').then((response) => response.json());
  if (session.signedIn) {
    await loadMe();
    return;
  }

  const stored = JSON.parse(localStorage.getItem('quantivitaSession') || 'null');
  if (stored?.accountId && stored?.syncToken) {
    accountInput.value = stored.accountId;
    tokenInput.value = stored.syncToken;
    await load(stored.accountId, stored.syncToken);
    return;
  }

  renderDashboard(seedEmptyData());
}

async function login(accountId, syncToken) {
  const response = await fetch('/api/accounts/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ accountId, syncToken }),
  });
  if (!response.ok) {
    loginStatus.textContent = 'Login failed. Check the account id and sync token from the iPhone app.';
    return;
  }
  localStorage.setItem('quantivitaSession', JSON.stringify({ accountId, syncToken }));
  await load(accountId, syncToken);
}

async function loadMe() {
  const response = await fetch('/api/me/health');
  if (!response.ok) {
    loginStatus.textContent = 'Session expired. Sign in again.';
    return;
  }
  const data = await response.json();
  currentSession = { mode: 'cookie', accountId: data.accountId };
  showSignedIn(data.accountId);
  csvLink.href = '/api/me/export.csv';
  csvLink.onclick = null;
  renderDashboard(data);
}

async function load(accountId, syncToken) {
  const response = await fetch(`/api/users/${encodeURIComponent(accountId)}/health`, {
    headers: { authorization: `Bearer ${syncToken}` },
  });
  if (!response.ok) {
    loginStatus.textContent = 'Session expired or unauthorized. Login again.';
    return;
  }
  const data = await response.json();
  currentSession = { mode: 'token', accountId, syncToken };
  showSignedIn(accountId);
  csvLink.href = '#';
  csvLink.onclick = async (event) => {
    event.preventDefault();
    const csvResponse = await fetch(`/api/users/${encodeURIComponent(accountId)}/export.csv`, {
      headers: { authorization: `Bearer ${syncToken}` },
    });
    const blob = await csvResponse.blob();
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${accountId}-quantivita.csv`;
    link.click();
    URL.revokeObjectURL(url);
  };
  renderDashboard(data);
}

async function syncProgressaWorkouts() {
  if (!currentSession) return;
  progressaSyncButton.disabled = true;
  progressaSyncButton.textContent = 'Syncing...';
  const url =
    currentSession.mode === 'cookie'
      ? '/api/me/progressa/workouts?limit=100'
      : `/api/users/${encodeURIComponent(currentSession.accountId)}/integrations/progressa/workouts?limit=100`;
  const response = await fetch(url, {
    headers:
      currentSession.mode === 'token'
        ? { authorization: `Bearer ${currentSession.syncToken}` }
        : {},
  });
  if (response.ok) {
    currentSession.mode === 'cookie'
      ? await loadMe()
      : await load(currentSession.accountId, currentSession.syncToken);
  } else {
    const body = await response.json().catch(() => ({}));
    loginStatus.textContent = body.error || 'Progressa sync failed.';
  }
  progressaSyncButton.disabled = false;
  progressaSyncButton.textContent = 'Sync Progressa';
}

function showSignedIn(accountId) {
  loginStatus.textContent = `Signed in as ${shortAccount(accountId)}`;
  authCard.hidden = true;
  document.querySelector('#sync-state').textContent = 'Synced';
  document.querySelector('#sync-copy').textContent = `${shortAccount(accountId)} is connected to this dashboard.`;
}

function renderDashboard(data) {
  const daily = data.daily || [];
  const workouts = data.workouts || [];
  const latest = daily.at(-1) || {};
  const previous = daily.at(-2) || {};
  const todayWorkouts = workoutsForDate(workouts, latest.date);
  const recovery = numberOrNull(latest.recoveryScore);
  const updatedAt = data.updatedAt ? new Date(data.updatedAt) : null;

  document.querySelector('#date-range').textContent = daily.length ? `Last ${daily.length} days` : 'No data yet';
  document.querySelector('#updated-at').textContent = updatedAt ? `Synced ${relativeTime(updatedAt)}` : 'Not synced';
  document.querySelector('#readiness-title').textContent = recovery == null
    ? 'Sync your iPhone to unlock readiness.'
    : readinessTitle(recovery);
  document.querySelector('#readiness-copy').textContent = readinessCopy(latest, previous, todayWorkouts);
  document.querySelector('#recovery-gauge').style.setProperty('--score', String(Math.max(0, Math.min(100, recovery || 0))));
  document.querySelector('#gauge-value').textContent = recovery == null ? '--' : formatNumber(recovery, 0);

  renderHeroSignals(latest, todayWorkouts);
  renderInsights(latest, previous, todayWorkouts);
  renderStats(data, todayWorkouts);
  renderChart('recovery-chart', daily, 'recoveryScore', 'var(--brand-strong)', { suffix: '%', min: 0, max: 100 });
  renderChart('sleep-chart', daily, 'sleepMinutes', 'var(--cyan)', { formatter: formatSleepShort });
  renderDualChart('heart-chart', daily, 'hrvMs', 'restingHeartBpm');
  renderActivityChart(daily);
  renderBodySystems(latest);
  renderWorkouts(todayWorkouts);
}

function renderHeroSignals(latest, workouts) {
  const tiles = [
    ['Sleep', formatSleep(latest.sleepMinutes), 'time asleep'],
    ['HRV', withUnit(latest.hrvMs, 'ms', 1), 'higher is calmer'],
    ['Resting HR', withUnit(latest.restingHeartBpm, 'bpm', 0), 'lower is easier'],
    ['Training', `${workouts.length}`, 'today'],
  ];
  document.querySelector('#hero-signals').innerHTML = tiles
    .map(([label, value, copy]) => `
      <div class="signal-tile">
        <span>${label}</span>
        <strong>${value}</strong>
        <small>${copy}</small>
      </div>
    `)
    .join('');
}

function renderStats(data, todayWorkouts) {
  const latest = (data.daily || []).at(-1) || {};
  const workouts = todayWorkouts || [];
  const totalEnergy = workouts.reduce((sum, workout) => sum + Number(workout.energyKcal || workout.totalEnergyKcal || 0), 0);
  const totalDistance = workouts.reduce((sum, workout) => sum + Number(workout.distanceMeters || 0), 0);
  const cards = [
    ['↗', 'Recovery', percent(latest.recoveryScore), trendCopy(latest.recoveryScore, (data.daily || []).at(-2)?.recoveryScore, 'pts')],
    ['◌', 'Sleep', formatSleep(latest.sleepMinutes), sleepQualityCopy(latest.sleepMinutes)],
    ['❤', 'HRV', withUnit(latest.hrvMs, 'ms', 1), trendCopy(latest.hrvMs, (data.daily || []).at(-2)?.hrvMs, 'ms')],
    ['⌁', 'Resting HR', withUnit(latest.restingHeartBpm, 'bpm', 0), trendCopy(latest.restingHeartBpm, (data.daily || []).at(-2)?.restingHeartBpm, 'bpm')],
    ['◆', 'Training', `${workouts.length}`, `${formatNumber(totalEnergy, 0)} kcal · ${formatNumber(totalDistance / 1000, 1)} km today`],
  ];
  stats.innerHTML = cards
    .map(([icon, label, value, meta]) => `
      <article class="stat">
        <div class="stat-icon">${icon}</div>
        <span>${label}</span>
        <strong>${value}</strong>
        <small>${meta}</small>
      </article>
    `)
    .join('');
}

function renderInsights(latest, previous, workouts) {
  const recovery = numberOrNull(latest.recoveryScore);
  const hrvDelta = delta(latest.hrvMs, previous.hrvMs);
  const sleep = numberOrNull(latest.sleepMinutes);
  const lastWorkout = workouts[0];
  const insights = [
    {
      title: recovery == null ? 'No readiness score yet' : recovery >= 75 ? 'Strong recovery window' : recovery >= 55 ? 'Moderate readiness' : 'Low readiness signal',
      copy: recovery == null
        ? 'Sync Quantivita API from your iPhone to populate this view.'
        : recovery >= 75
          ? 'Your recovery score supports a normal training day. Keep an eye on HRV and resting heart rate.'
          : recovery >= 55
            ? 'A balanced day makes sense: steady movement, hydration, and a realistic sleep target.'
            : 'Consider reducing intensity until sleep, HRV, or resting heart rate improves.',
    },
    {
      title: sleep == null ? 'Sleep data missing' : 'Sleep consistency',
      copy: sleep == null
        ? 'Apple Health sleep minutes will appear here after the next sync.'
        : `${formatSleep(sleep)} logged. ${sleepQualityCopy(sleep)}.`,
    },
    {
      title: 'Cardiac trend',
      copy: hrvDelta == null
        ? 'HRV trend needs at least two synced days.'
        : `HRV changed ${formatSigned(hrvDelta, 1)} ms versus the previous synced day.`,
    },
    {
      title: lastWorkout ? `Latest: ${lastWorkout.title || 'Workout'}` : 'No workouts yet',
      copy: lastWorkout
        ? `${formatDate(lastWorkout.startTime)} · ${withUnit(lastWorkout.durationMinutes, 'min', 0)} · ${withUnit(lastWorkout.energyKcal || lastWorkout.totalEnergyKcal, 'kcal', 0)}.`
        : 'Merged workouts and HealthKit workouts will appear here after sync.',
    },
  ];
  document.querySelector('#insights').innerHTML = insights
    .map((item) => `<div class="insight"><strong>${escapeHtml(item.title)}</strong><p>${escapeHtml(item.copy)}</p></div>`)
    .join('');
}

function renderChart(id, rows, field, color, options = {}) {
  const values = rows.map((row) => numberOrNull(row[field])).filter((value) => value != null);
  document.querySelector(`#${id}`).innerHTML = values.length
    ? svgLine(values, color, options)
    : '<div class="empty">No trend data yet.</div>';
}

function renderDualChart(id, rows, leftField, rightField) {
  const hrv = rows.map((row) => numberOrNull(row[leftField])).filter((value) => value != null);
  const rhr = rows.map((row) => numberOrNull(row[rightField])).filter((value) => value != null);
  document.querySelector(`#${id}`).innerHTML = hrv.length || rhr.length
    ? svgLine(hrv, 'var(--brand-strong)', { height: 125 }) + svgLine(rhr, 'var(--rose)', { height: 125 })
    : '<div class="empty">No HRV or heart-rate data yet.</div>';
}

function svgLine(values, color, options = {}) {
  const width = 920;
  const height = options.height || 250;
  const max = options.max ?? Math.max(...values, 1);
  const min = options.min ?? Math.min(...values, 0);
  const spread = Math.max(max - min, 1);
  const points = values.map((value, index) => {
    const x = values.length <= 1 ? width / 2 : (index / (values.length - 1)) * (width - 48) + 24;
    const y = height - ((value - min) / spread) * (height - 54) - 28;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  });
  const last = values.at(-1);
  const label = options.formatter ? options.formatter(last) : `${formatNumber(last, 0)}${options.suffix || ''}`;
  return `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Trend chart">
      <line class="chart-grid-line" x1="24" y1="${height - 28}" x2="${width - 24}" y2="${height - 28}" />
      <line class="chart-grid-line" x1="24" y1="28" x2="${width - 24}" y2="28" />
      <polyline points="${points.join(' ')}" fill="none" stroke="${color}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" />
      <circle cx="${points.at(-1)?.split(',')[0] || 24}" cy="${points.at(-1)?.split(',')[1] || 24}" r="7" fill="${color}" />
      <text class="chart-label" x="${width - 24}" y="22" text-anchor="end">${label}</text>
    </svg>
  `;
}

function renderActivityChart(rows) {
  const values = rows.map((row) => ({
    energy: Number(row.activeEnergyKcal || 0),
    steps: Number(row.steps || 0),
    label: row.date ? row.date.slice(5) : '',
  }));
  if (!values.some((row) => row.energy || row.steps)) {
    document.querySelector('#activity-chart').innerHTML = '<div class="empty">No activity data yet.</div>';
    return;
  }
  const width = 720;
  const height = 250;
  const maxEnergy = Math.max(...values.map((row) => row.energy), 1);
  const maxSteps = Math.max(...values.map((row) => row.steps), 1);
  const slot = (width - 48) / Math.max(values.length, 1);
  const bars = values.map((row, index) => {
    const x = 24 + index * slot + slot * 0.18;
    const energyHeight = (row.energy / maxEnergy) * 150;
    const stepHeight = (row.steps / maxSteps) * 150;
    return `
      <rect x="${x.toFixed(1)}" y="${(height - 42 - energyHeight).toFixed(1)}" width="${Math.max(slot * 0.24, 7).toFixed(1)}" height="${energyHeight.toFixed(1)}" rx="7" fill="var(--brand)" />
      <rect x="${(x + slot * 0.3).toFixed(1)}" y="${(height - 42 - stepHeight).toFixed(1)}" width="${Math.max(slot * 0.24, 7).toFixed(1)}" height="${stepHeight.toFixed(1)}" rx="7" fill="var(--blue)" />
    `;
  });
  document.querySelector('#activity-chart').innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Energy and steps bars">
      <line class="chart-grid-line" x1="24" y1="${height - 42}" x2="${width - 24}" y2="${height - 42}" />
      ${bars.join('')}
      <text class="chart-label" x="24" y="24">Energy kcal</text>
      <text class="chart-label" x="${width - 24}" y="24" text-anchor="end">Steps</text>
    </svg>
  `;
}

function renderBodySystems(latest) {
  const systems = [
    ['Recovery', latest.recoveryScore, 100],
    ['Sleep', clamp((Number(latest.sleepMinutes || 0) / 480) * 100, 0, 100), 100],
    ['Cardio', cardioScore(latest), 100],
    ['Oxygen', latest.oxygenSaturation, 100],
    ['Activity', clamp((Number(latest.steps || 0) / 10000) * 100, 0, 100), 100],
  ];
  document.querySelector('#body-systems').innerHTML = systems
    .map(([label, value, max]) => {
      const score = clamp(Number(value || 0), 0, max);
      return `
        <div class="system-row">
          <span>${label}</span>
          <div class="system-track"><div class="system-fill" style="width: ${(score / max) * 100}%"></div></div>
          <strong>${score ? formatNumber(score, 0) : '--'}</strong>
        </div>
      `;
    })
    .join('');
}

function renderWorkouts(workouts) {
  const container = document.querySelector('#workouts');
  if (!workouts.length) {
    container.innerHTML = '<div class="empty">No workouts for this synced day.</div>';
    return;
  }
  container.innerHTML = workouts
    .slice(0, 12)
    .map((workout) => `
      <div class="workout ${workout.source === 'progressa' ? 'workout-progressa' : ''}">
        <strong>${escapeHtml(workout.title || 'Workout')}</strong>
        <span>${escapeHtml(workout.source === 'progressa' ? 'Progressa' : 'HealthKit')}</span>
        <span>${formatDate(workout.startTime)}</span>
        <span>${withUnit(workout.durationMinutes, 'min', 0)}</span>
        <span>${workoutDetailsLabel(workout)}</span>
      </div>
    `)
    .join('');
}

function workoutDetailsLabel(workout) {
  const details = workout.progressaDetails || {};
  if (workout.source === 'progressa') {
    const sets = Number(details.totalSets || 0);
    const exercises = Number(details.exerciseCount || 0);
    const volume = Number(details.totalVolumeKg || 0);
    return `${sets} sets · ${exercises} exercises${volume ? ` · ${formatNumber(volume, 0)} kg` : ''}`;
  }
  return `${withUnit(workout.energyKcal || workout.totalEnergyKcal, 'kcal', 0)} · ${formatNumber(Number(workout.distanceMeters || 0) / 1000, 1)} km`;
}

function readinessTitle(score) {
  if (score >= 80) return 'You look ready for meaningful work.';
  if (score >= 65) return 'Solid baseline, watch intensity.';
  if (score >= 45) return 'Mixed recovery signals today.';
  return 'Recovery is asking for a lighter day.';
}

function readinessCopy(latest, previous, workouts) {
  const parts = [];
  const recoveryDelta = delta(latest.recoveryScore, previous.recoveryScore);
  if (recoveryDelta != null) parts.push(`Recovery ${formatSigned(recoveryDelta, 0)} pts vs previous sync`);
  if (latest.sleepMinutes) parts.push(`${formatSleep(latest.sleepMinutes)} sleep`);
  if (latest.restingHeartBpm) parts.push(`${formatNumber(latest.restingHeartBpm, 0)} bpm resting HR`);
  if (workouts.length) parts.push(`${workouts.length} workouts today`);
  return parts.length ? `${parts.join(' · ')}.` : 'Your synced recovery, sleep, HRV, activity, and workout data will appear here.';
}

function workoutsForDate(workouts, dateString) {
  if (!dateString) return [];
  return workouts.filter((workout) => localDateString(workout.startTime) === dateString);
}

function localDateString(value) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function cardioScore(latest) {
  const hrv = Number(latest.hrvMs || 0);
  const rhr = Number(latest.restingHeartBpm || 0);
  if (!hrv && !rhr) return 0;
  const hrvScore = clamp((hrv / 80) * 100, 0, 100);
  const rhrScore = rhr ? clamp(100 - Math.max(rhr - 45, 0) * 2, 0, 100) : hrvScore;
  return (hrvScore + rhrScore) / 2;
}

function seedEmptyData() {
  return { accountId: '', daily: [], workouts: [], integrations: {}, updatedAt: null };
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function delta(value, previous) {
  const current = numberOrNull(value);
  const before = numberOrNull(previous);
  return current == null || before == null ? null : current - before;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function formatNumber(value, decimals = 0) {
  const number = numberOrNull(value);
  if (number == null) return '--';
  return new Intl.NumberFormat('en-US', {
    maximumFractionDigits: decimals,
    minimumFractionDigits: decimals,
  }).format(number);
}

function formatSigned(value, decimals = 0) {
  const number = numberOrNull(value);
  if (number == null) return '--';
  return `${number > 0 ? '+' : ''}${formatNumber(number, decimals)}`;
}

function withUnit(value, unit, decimals = 0) {
  const number = numberOrNull(value);
  return number == null || number === 0 ? '--' : `${formatNumber(number, decimals)} ${unit}`;
}

function percent(value) {
  const number = numberOrNull(value);
  return number == null ? '--' : `${formatNumber(number, 0)}%`;
}

function formatSleep(minutes) {
  const number = numberOrNull(minutes);
  if (number == null || number <= 0) return '--';
  const hours = Math.floor(number / 60);
  const mins = Math.round(number % 60);
  return `${hours}h ${mins}m`;
}

function formatSleepShort(minutes) {
  const number = numberOrNull(minutes);
  if (number == null || number <= 0) return '--';
  return `${formatNumber(number / 60, 1)}h`;
}

function sleepQualityCopy(minutes) {
  const number = numberOrNull(minutes);
  if (number == null || number <= 0) return 'No sleep sync yet';
  if (number >= 450) return 'Great sleep volume';
  if (number >= 390) return 'Solid sleep volume';
  if (number >= 330) return 'Could use more sleep';
  return 'Low sleep volume';
}

function trendCopy(value, previous, unit) {
  const change = delta(value, previous);
  if (change == null) return 'Need another synced day';
  return `${formatSigned(change, unit === 'pts' ? 0 : 1)} ${unit} vs previous sync`;
}

function formatDate(value) {
  if (!value) return '--';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '--';
  return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric' }).format(date);
}

function relativeTime(date) {
  const diffMs = date.getTime() - Date.now();
  const minutes = Math.round(diffMs / 60000);
  const absolute = Math.abs(minutes);
  const formatter = new Intl.RelativeTimeFormat('en-US', { numeric: 'auto' });
  if (absolute < 60) return formatter.format(minutes, 'minute');
  const hours = Math.round(minutes / 60);
  if (Math.abs(hours) < 48) return formatter.format(hours, 'hour');
  return formatter.format(Math.round(hours / 24), 'day');
}

function shortAccount(accountId) {
  const value = String(accountId || '');
  return value.length > 18 ? `${value.slice(0, 10)}…${value.slice(-6)}` : value;
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}
