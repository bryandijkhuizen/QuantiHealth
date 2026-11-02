-- Apply to the Progressa Supabase database before distributing the new app.
begin;

-- NULL/NULL represents historical workouts whose duration was never recorded.
alter table public.workouts add column if not exists start_time timestamptz;
alter table public.workouts add column if not exists end_time timestamptz;
alter table public.workouts add constraint workout_valid_times
  check (end_time is null or (start_time is not null and end_time >= start_time));
create unique index workouts_one_active_per_user on public.workouts (user_id)
  where start_time is not null and end_time is null;

alter table public.workout_exercise_blocks add column if not exists sequence_id uuid;
alter table public.workout_exercise_blocks add column if not exists sequence_round integer;
alter table public.workout_exercise_blocks add constraint workout_sequence_valid
  check ((sequence_id is null and sequence_round is null) or
         (sequence_id is not null and sequence_round is not null and sequence_round between 1 and 20));

-- Create the whole circuit atomically; empty blocks are planned exercises, not logged sets.
create function public.add_workout_sequence(p_workout_id uuid, p_exercise_ids uuid[], p_rounds integer)
returns void language plpgsql security invoker set search_path = public as $$
declare
  sequence uuid := gen_random_uuid();
  block uuid;
  exercise uuid;
  round_number integer;
  position integer;
begin
  if auth.uid() is null or not exists (
    select 1 from workouts where id = p_workout_id and user_id = auth.uid()
  ) then raise exception 'Workout not found'; end if;
  if p_rounds is null or p_rounds not between 1 and 20 or
     coalesce(cardinality(p_exercise_ids), 0) not between 2 and 12 then
    raise exception 'Choose 2–12 exercises and 1–20 rounds';
  end if;
  -- Serialize simultaneous sequence additions to this workout.
  perform 1 from workouts where id = p_workout_id for update;
  select coalesce(max(sort_order), -1) + 1 into position
    from workout_exercise_blocks where workout_id = p_workout_id;
  for round_number in 1..p_rounds loop
    foreach exercise in array p_exercise_ids loop
      if not exists (select 1 from exercises where id = exercise and is_active
        and (user_id is null or user_id = auth.uid())) then
        raise exception 'Exercise unavailable';
      end if;
      block := gen_random_uuid();
      insert into workout_exercise_blocks(id, workout_id, exercise_id, sort_order, sequence_id, sequence_round)
        values (block, p_workout_id, exercise, position, sequence, round_number);
      insert into workout_exercise_block_order(workout_id, exercise_block_id, sort_order)
        values (p_workout_id, block, position);
      position := position + 1;
    end loop;
  end loop;
end;
$$;
revoke all on function public.add_workout_sequence(uuid, uuid[], integer) from public;
grant execute on function public.add_workout_sequence(uuid, uuid[], integer) to authenticated;
commit;
