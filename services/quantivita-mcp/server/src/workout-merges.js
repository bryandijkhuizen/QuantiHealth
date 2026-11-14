import crypto from 'node:crypto';

const number = value => value !== null && value !== undefined && Number.isFinite(Number(value)) ? Number(value) : null;
const positive = value => number(value) > 0 ? Number(value) : null;
const millis = value => Date.parse(value);
const telemetry = workout => workout.telemetry || workout;
const seconds = intervals => intervals.reduce((sum, [a, b]) => sum + (b - a) / 1000, 0);

export function unionIntervals(intervals) {
  const result = [];
  for (const [start, end] of intervals.filter(([a, b]) => Number.isFinite(a) && b > a).sort((a, b) => a[0] - b[0])) {
    const last = result.at(-1);
    if (last && start <= last[1]) last[1] = Math.max(last[1], end);
    else result.push([start, end]);
  }
  return result;
}

function bounds(workout) {
  const start = millis(workout.startTime);
  const end = millis(telemetry(workout).workoutEndTime || workout.endTime);
  return [start, Number.isFinite(end) && end > start ? end : start + Number(workout.durationMinutes || 0) * 60000];
}

function activeIntervals(workout) {
  const [start, end] = bounds(workout);
  const events = (telemetry(workout).workoutEvents || []).filter(e => ['pause', 'resume', 'motionPaused', 'motionResumed'].includes(e.type)).sort((a,b) => millis(a.startTime) - millis(b.startTime));
  let cursor = start;
  let paused = false;
  const result = [];
  for (const event of events) {
    const time = Math.max(start, Math.min(end, millis(event.startTime)));
    if (!Number.isFinite(time)) continue;
    if (['pause', 'motionPaused'].includes(event.type) && !paused) {
      if (time > cursor) result.push([cursor, time]);
      paused = true;
    } else if (['resume', 'motionResumed'].includes(event.type) && paused) {
      cursor = time; paused = false;
    }
  }
  if (!paused && cursor < end) result.push([cursor, end]);
  return result;
}

function provenance(workout) {
  return { id: workout.id, title: workout.title, startTime: workout.startTime,
    endTime: Number.isFinite(bounds(workout)[1]) ? new Date(bounds(workout)[1]).toISOString() : null, durationMinutes: workout.durationMinutes,
    sourceName: workout.sourceName || workout.source || 'Unknown',
    sourceBundleIdentifier: workout.sourceBundleIdentifier || null,
    provider: workout.provider || workout.sourceName || workout.source || 'unknown',
    importedVia: workout.importedVia || workout.source || 'unknown', externalWorkoutId: workout.externalWorkoutId || null };
}

export function previewMerge(workouts, ids, strategy = 'concatenate') {
  if (!Array.isArray(ids) || ids.length < 2 || ids.length > 100 || new Set(ids).size !== ids.length) throw new Error('Select 2–100 different activities.');
  const selected = ids.map(id => workouts.find(w => w.id === id));
  if (selected.some(w => !w)) throw new Error('An activity is unavailable or already combined. Refresh the activity list.');
  if (selected.some(w => w.merge)) throw new Error('Undo the existing combination before combining its parts again.');
  if (new Set(selected.map(w => w.typeCode)).size !== 1 || selected.some(w => !w.typeCode || w.progressaDetails)) throw new Error('Choose activities of the same sport. Strength workouts cannot be combined here.');
  if (!['concatenate', 'time_only', 'duplicate'].includes(strategy)) throw new Error('Unknown merge strategy.');
  if (selected.some(w => !Number.isFinite(Number(w.durationMinutes)) || Number(w.durationMinutes) <= 0)) throw new Error('Every activity needs a positive duration.');
  if (selected.some(w => bounds(w).some(t => !Number.isFinite(t)) || bounds(w)[1] <= bounds(w)[0])) throw new Error('Every activity needs a valid start and duration.');
  const intervals = selected.flatMap(activeIntervals);
  const active = unionIntervals(intervals);
  const overlapSeconds = Math.max(0, seconds(intervals) - seconds(active));
  const start = Math.min(...selected.map(w => bounds(w)[0]));
  const end = Math.max(...selected.map(w => bounds(w)[1]));
  const warnings = [];
  if (overlapSeconds > 1) warnings.push('These activities overlap. Choose one authoritative duplicate, or combine time only; distance and energy will be unknown.');
  if ((end - start) / 1000 - seconds(active) > 3600) warnings.push('There is more than an hour of gaps or pauses. Gaps are excluded from active duration.');
  const unlocatedPauses = overlapSeconds > 1 && selected.some(w => Math.abs(seconds(activeIntervals(w)) - Number(w.durationMinutes) * 60) > 1);
  if (unlocatedPauses) warnings.push('Pause timing is incomplete. Use one authoritative source; active time cannot be reconciled from these summaries.');
  const canMerge = (overlapSeconds <= 1 || strategy !== 'concatenate') && !(strategy === 'time_only' && unlocatedPauses);
  const primary = selected[0];
  // Without pause events, HealthKit duration is authoritative for disjoint records.
  const durationMinutes = overlapSeconds > 1 ? seconds(active) / 60 : selected.reduce((s,w) => s + Number(w.durationMinutes || 0), 0);
  const unknownTotals = overlapSeconds > 1 && strategy === 'time_only';
  const sum = key => unknownTotals || selected.some(w => number(w[key]) === null || (key === 'distanceMeters' && w.distanceAvailable === false) || (['energyKcal', 'totalEnergyKcal'].includes(key) && w.energyAvailable === false)) ? null : selected.reduce((s,w) => s + Number(w[key]), 0);
  const weighted = (key, allowZero = false) => {
    const rows = selected.filter(w => (allowZero ? number(w[key]) !== null : positive(w[key]) !== null) && w.durationMinutes > 0);
    if (overlapSeconds > 1 || !rows.length) return null;
    return rows.reduce((s,w) => s + Number(w[key]) * w.durationMinutes, 0) / rows.reduce((s,w) => s + w.durationMinutes, 0);
  };
  const sampleMean = (arrayKey, valueKey) => {
    let total = 0; let weight = 0;
    if (overlapSeconds > 1 || selected.some(w => !(telemetry(w)[arrayKey] || []).length)) return null;
    for (const source of selected) {
      let lastEnd = -Infinity;
      for (const sample of [...telemetry(source)[arrayKey]].sort((a,b) => millis(a.time) - millis(b.time))) {
        const a = Math.max(millis(sample.time), bounds(source)[0]);
        const b = Math.min(millis(sample.endTime), bounds(source)[1]);
        const value = number(sample[valueKey]);
        if (value === null || value < 0 || (valueKey === 'bpm' && value === 0) || !Number.isFinite(b) || b <= a || a < lastEnd) return null;
        total += value * (b - a); weight += b - a; lastEnd = b;
      }
    }
    return weight > 0 ? total / weight : null;
  };
  const maximum = key => { const values = selected.map(w => number(w[key])).filter(v => v !== null); return values.length ? Math.max(...values) : null; };
  const workout = strategy === 'duplicate' ? { ...primary } : {
    title: `${primary.title || 'Workout'} · combined`, source: 'quantivita',
    startTime: new Date(start).toISOString(), endTime: new Date(end).toISOString(),
    durationMinutes, elapsedDurationMinutes: (end - start) / 60000,
    energyKcal: sum('energyKcal'), totalEnergyKcal: sum('totalEnergyKcal'), distanceMeters: sum('distanceMeters'),
    averageHeartRate: sampleMean('heartRateSamples', 'bpm') ?? weighted('averageHeartRate'), maxHeartRate: positive(maximum('maxHeartRate')),
    avgPowerWatts: sampleMean('powerSamples', 'value') ?? weighted('avgPowerWatts', true), maxPowerWatts: maximum('maxPowerWatts'),
    avgCadenceRpm: sampleMean('cadenceSamples', 'value') ?? weighted('avgCadenceRpm', true), maxCadenceRpm: maximum('maxCadenceRpm'), normalizedPowerWatts: null,
    typeCode: primary.typeCode, hasRoute: false,
  };
  workout.id = 'preview';
  workout.distanceAvailable = workout.distanceAvailable !== false && workout.distanceMeters != null;
  workout.energyAvailable = workout.energyAvailable !== false && workout.energyKcal != null;
  workout.metricsNote = strategy === 'duplicate' ? 'All measurements use the first selected source. Other records are retained as provenance.'
    : unknownTotals ? 'Overlapping summary data cannot be reconciled reliably. Distance, energy and averages are unknown; duration uses the union of recorded intervals.'
    : 'Averages use measured sample intervals when available for every source, otherwise duration-weighted source summaries (derived). Missing measurements are excluded. Gaps are excluded. Normalized power is unavailable for combined activities.';
  return { workout, sources: selected.map(provenance), overlapSeconds, warnings, canMerge, strategy };
}

export function createMerge(workouts, merges, ids, strategy, accountId) {
  const existing = merges.find(m => !m.undoneAt && m.strategy === strategy && (strategy !== 'duplicate' || m.sourceWorkoutIds[0] === ids?.[0]) && JSON.stringify([...m.sourceWorkoutIds].sort()) === JSON.stringify([...(ids || [])].sort()));
  if (existing) return existing;
  const used = new Set(merges.filter(m => !m.undoneAt).flatMap(m => m.sourceWorkoutIds));
  const usedIdentities = new Set(workouts.filter(w => used.has(w.id)).map(identity).filter(Boolean));
  if ((ids || []).some(id => used.has(id) || usedIdentities.has(identity(workouts.find(w => w.id === id) || {})))) throw new Error('An activity already belongs to a combination. Undo it first.');
  const preview = previewMerge(workouts, ids, strategy);
  if (!preview.canMerge) throw new Error('Choose how to handle the overlapping activities before confirming.');
  return { id: crypto.randomUUID(), sourceWorkoutIds: ids, strategy, createdAt: new Date().toISOString(), createdBy: accountId };
}

// Only a provider-issued identity is strong enough for automatic deduplication.
function identity(workout) {
  const provider = workout.provider;
  return provider && workout.externalWorkoutId ? `${provider}:${workout.externalWorkoutId}` : null;
}

export function canonicalWorkouts(workouts = [], merges = []) {
  workouts = workouts.map(w => ({...w, averageHeartRate: positive(w.averageHeartRate), maxHeartRate: positive(w.maxHeartRate)}));
  const consumed = new Set();
  const canonical = [];
  for (const merge of merges.filter(m => !m.undoneAt)) {
    const parts = merge.sourceWorkoutIds.map(id => workouts.find(w => w.id === id));
    if (parts.some(w => !w)) continue;
    const preview = previewMerge(parts, merge.sourceWorkoutIds, merge.strategy);
    // A changed source may introduce overlap after confirmation: never silently add it twice.
    if (!preview.canMerge) {
      const timePreview = previewMerge(parts, merge.sourceWorkoutIds, 'time_only');
      Object.assign(preview, timePreview.canMerge ? timePreview : previewMerge(parts, merge.sourceWorkoutIds, 'duplicate'));
      preview.warnings.push('Source timing changed after merging. Review this combination.');
    }
    canonical.push({ ...preview.workout, id: `merge:${merge.id}`, merge: { ...merge, sources: preview.sources, warnings: preview.warnings } });
    merge.sourceWorkoutIds.forEach(id => consumed.add(id));
    for (const row of workouts) {
      if (parts.some(part => identity(part) && identity(part) === identity(row) && part.typeCode === row.typeCode && Math.abs(millis(part.startTime) - millis(row.startTime)) < 60000)) {
        consumed.add(row.id);
        if (!canonical.at(-1).merge.sourceWorkoutIds.includes(row.id)) {
          canonical.at(-1).merge.sourceWorkoutIds = [...canonical.at(-1).merge.sourceWorkoutIds, row.id];
          canonical.at(-1).merge.sources.push(provenance(row));
        }
      }
    }
  }
  const identities = new Map();
  for (const workout of workouts.filter(w => !consumed.has(w.id))) {
    const key = identity(workout);
    const duplicate = key && identities.get(key);
    if (duplicate && duplicate.typeCode === workout.typeCode && Math.abs(millis(duplicate.startTime) - millis(workout.startTime)) < 60000) {
      const sources = [...duplicate.duplicateSources, provenance(workout)];
      const completeness = row => ['avgPowerWatts','maxPowerWatts','avgCadenceRpm','maxCadenceRpm','averageHeartRate','maxHeartRate'].filter(key => number(row[key]) !== null).length;
      if (completeness(workout) > completeness(duplicate)) Object.assign(duplicate, workout);
      duplicate.duplicateSources = sources;
      duplicate.metricsNote = 'Automatically deduplicated by provider identity. Measurements use the source with the most available cycling and heart-rate summary fields.';
      consumed.add(workout.id);
    } else {
      const copy = { ...workout, duplicateSources: [provenance(workout)] };
      canonical.push(copy);
      if (key) identities.set(key, copy);
    }
  }
  return canonical.sort((a,b) => millis(b.startTime) - millis(a.startTime));
}
