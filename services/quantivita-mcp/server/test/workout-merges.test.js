import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalWorkouts, createMerge, previewMerge } from '../src/workout-merges.js';
const ride = (id, minute, extra = {}) => ({ id, title: 'Cycling', typeCode: 3, startTime: new Date(Date.UTC(2026,10,14,10,minute)).toISOString(), durationMinutes: 20, distanceMeters: 8000, energyKcal: 200, totalEnergyKcal: 200, averageHeartRate: 120, maxHeartRate: 150, ...extra });

test('separate segments exclude gaps, aggregate once, survive reimport and undo', () => {
  const rows = [ride('a',0), ride('b',30,{averageHeartRate: 140})];
  const merge = createMerge(rows, [], ['a','b'], 'concatenate', 'alice');
  const result = canonicalWorkouts(rows, [merge]);
  assert.equal(result.length, 1);
  assert.equal(result[0].durationMinutes, 40);
  assert.equal(result[0].elapsedDurationMinutes, 50);
  assert.equal(result[0].distanceMeters, 16000);
  assert.equal(result[0].averageHeartRate, 130);
  assert.equal(result[0].merge.sources.length, 2);
  assert.equal(canonicalWorkouts(rows.map(w => ({...w})), [merge]).length, 1);
  assert.deepEqual(createMerge(rows, [merge], ['b','a'], 'concatenate', 'alice'), merge);
  assert.equal(canonicalWorkouts(rows, [{...merge, undoneAt: new Date().toISOString()}]).length, 2);
});
test('overlap needs an explicit strategy; time-only never doubles distance or energy', () => {
  const rows = [ride('a',0), ride('b',10)];
  assert.equal(previewMerge(rows, ['a','b']).canMerge, false);
  assert.throws(() => createMerge(rows, [], ['a','b'], 'concatenate', 'a'));
  const merged = previewMerge(rows, ['a','b'], 'time_only');
  assert.equal(merged.workout.durationMinutes, 30);
  assert.equal(merged.workout.energyKcal, null);
  assert.equal(merged.workout.distanceMeters, null);
  assert.equal(merged.workout.averageHeartRate, null);
  const duplicate = previewMerge(rows, ['a','b'], 'duplicate');
  assert.equal(duplicate.workout.distanceMeters, 8000);
  assert.equal(duplicate.workout.durationMinutes, 20);
});
test('pause intervals do not inflate active duration', () => {
  const rows = [ride('a',0,{durationMinutes: 15, workoutEndTime: '2026-11-14T10:20:00Z',workoutEvents:[{type:'pause',startTime:'2026-11-14T10:05:00Z'},{type:'resume',startTime:'2026-11-14T10:10:00Z'}]}),ride('b',10)];
  assert.equal(previewMerge(rows,['a','b'],'time_only').workout.durationMinutes,25);
});
test('unknown heart rate stays null and measured zero power stays zero', () => {
  const preview = previewMerge([ride('a',0,{averageHeartRate:0, maxHeartRate:0,avgPowerWatts:0}),ride('b',30,{averageHeartRate:null,maxHeartRate:null,avgPowerWatts:0})],['a','b']);
  assert.equal(preview.workout.averageHeartRate,null);
  assert.equal(preview.workout.maxHeartRate,null);
  assert.equal(preview.workout.avgPowerWatts,0);
});
test('reject missing or mixed-sport sources and repeated membership', () => {
  const rows = [ride('a',0),ride('b',30),ride('c',60,{typeCode:1})];
  assert.throws(() => previewMerge(rows,['a','missing']));
  assert.throws(() => previewMerge(rows,['a','c']));
  assert.throws(() => previewMerge(rows,['a','a']));
  const merge = createMerge(rows,[],['a','b'],'concatenate','alice');
  assert.throws(() => createMerge(rows,[merge],['a','c'],'concatenate','alice'));
});
test('automatic dedup requires provider identity and retains provenance', () => {
  const a = ride('a',0,{provider:'strava',externalWorkoutId:'42'});
  const b = ride('b',0,{provider:'strava',externalWorkoutId:'42',avgPowerWatts:200});
  const result = canonicalWorkouts([a,b]);
  assert.equal(result.length,1);
  assert.equal(result[0].duplicateSources.length,2);
  assert.equal(result[0].avgPowerWatts,200);
  assert.equal(canonicalWorkouts([a, {...b,externalWorkoutId:'43'}]).length,2);
  assert.equal(canonicalWorkouts([ride('a',0),ride('b',0)]).length,2);
});

test('a newly imported copy of a merged source remains hidden', () => {
  const a = ride('a',0,{provider:'strava',externalWorkoutId:'42'});
  const b = ride('b',30);
  const merge = createMerge([a,b],[],['a','b'],'concatenate','alice');
  const result = canonicalWorkouts([a,b,{...a,id:'reimported-copy'}],[merge]);
  assert.equal(result.length,1);
  assert.ok(result[0].merge.sourceWorkoutIds.includes('reimported-copy'));
  assert.equal(result[0].distanceMeters,16000);
});
test('sample means weight actual intervals, not gaps or simple sample count', () => {
  const a = ride('a',0,{heartRateSamples:[{time:'2026-11-14T10:00:00Z',endTime:'2026-11-14T10:00:10Z',bpm:100}]});
  const b = ride('b',30,{heartRateSamples:[{time:'2026-11-14T10:30:00Z',endTime:'2026-11-14T10:30:30Z',bpm:140}]});
  assert.equal(previewMerge([a,b],['a','b']).workout.averageHeartRate,130);
});
test('incomplete pause timing cannot be presented as known union duration', () => {
  const rows = [ride('a',0,{workoutEndTime:'2026-11-14T10:30:00Z'}),ride('b',10)];
  assert.equal(previewMerge(rows,['a','b'],'time_only').canMerge,false);
  assert.equal(previewMerge(rows,['a','b'],'duplicate').canMerge,true);
});
