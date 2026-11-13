begin;
create table public.exercise_load_preferences (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  base_weight_kg numeric not null check (base_weight_kg >= 0 and base_weight_kg < 'Infinity'::numeric),
  primary key(user_id, exercise_id)
);
alter table public.exercise_load_preferences enable row level security;
create policy own_exercise_load on public.exercise_load_preferences for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and exists
    (select 1 from public.exercises e where e.id = exercise_id and (e.user_id is null or e.user_id = auth.uid())));
grant select,insert,update,delete on public.exercise_load_preferences to authenticated;
alter table public.sets add column base_weight_kg numeric not null default 0;
alter table public.sets add column added_weight_kg numeric generated always as (weight_kg - base_weight_kg) stored;
-- Legacy clients send totals. New inserts request a snapshot by explicitly sending a null base.
create function public.snapshot_exercise_load() returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.base_weight_kg is null then
    select coalesce((select p.base_weight_kg from exercise_load_preferences p
      where p.user_id = new.user_id and p.exercise_id = new.exercise_id), 0) into new.base_weight_kg;
    if new.base_weight_kg > 0 then
      new.weight_kg := coalesce(new.weight_kg,0) + new.base_weight_kg;
    end if;
  elsif tg_op = 'UPDATE' and (new.weight_kg is null or new.weight_kg < new.base_weight_kg) then
    new.base_weight_kg := 0;
  end if;
  return new;
end $$;
create trigger snapshot_exercise_load before insert or update of weight_kg, base_weight_kg on public.sets
  for each row execute function public.snapshot_exercise_load();
alter table public.sets add constraint valid_base_load check
  (base_weight_kg >= 0 and (base_weight_kg = 0 or weight_kg is not null and weight_kg >= base_weight_kg));
-- Service endpoint authenticates the Progressa owner before calling this aggregate.
create function public.progress_index(p_user_id uuid, p_from date default null, p_to date default null)
returns jsonb language sql stable security invoker set search_path = public as $$
  with eligible as (
    select e.id, e.name, (w.created_at at time zone 'UTC')::date as day,
      s.weight_kg as total, s.base_weight_kg as base, s.added_weight_kg as added, s.reps,
      s.weight_kg * (30::numeric + s.reps) / 30 as estimate, s.id as set_id
    from sets s join workouts w on w.id = s.workout_id and w.user_id = s.user_id
    join exercises e on e.id = s.exercise_id
    where s.user_id = p_user_id and s.weight_kg > 0 and s.reps > 0
      and not coalesce(s.is_warmup,false) and coalesce(e.weight_type::text,'standard') = 'standard'
  ), daily as (
    select distinct on (id,day) id,name,day,total,base,added,reps,estimate
    from eligible where (p_from is null or day >= p_from) and (p_to is null or day <= p_to)
    order by id,day,estimate desc,set_id
  ), endpoints as (
    select id,min(day) as first_day,max(day) as last_day,count(*) as days from daily group by id
  )
  select jsonb_build_object(
    'loggedDates', coalesce((select jsonb_agg(day order by day) from (select distinct day from eligible) d),'[]'),
    'exercises', coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.name,
      'days',x.days,'baseline',to_jsonb(f)-'id'-'name','current',to_jsonb(l)-'id'-'name',
      'index', l.estimate / f.estimate) order by f.name,f.id)
      from endpoints x join daily f on f.id=x.id and f.day=x.first_day
      join daily l on l.id=x.id and l.day=x.last_day),'[]'))
$$;
revoke all on function public.progress_index(uuid,date,date) from public,anon,authenticated;
grant execute on function public.progress_index(uuid,date,date) to service_role;
commit;
