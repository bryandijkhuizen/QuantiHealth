-- Run in a disposable database with the migration and representative tables installed.
do $$
declare
  u uuid := gen_random_uuid(); e uuid := gen_random_uuid(); w uuid := gen_random_uuid();
  w2 uuid := gen_random_uuid(); result jsonb;
begin
  insert into auth.users values(u);
  insert into exercises(id,user_id,weight_type,name) values(e,u,'standard','Leg Press');
  insert into workouts(id,user_id,created_at) values(w,u,'2026-09-21T12:00:00Z'),(w2,u,'2026-11-11T12:00:00Z');
  insert into exercise_load_preferences values(u,e,10);
  insert into sets(user_id,exercise_id,workout_id,weight_kg,reps,base_weight_kg)
    values(u,e,w,102.5,10,null),(u,e,w2,125,12,null);
  update exercise_load_preferences set base_weight_kg=20 where user_id=u;
  insert into sets(user_id,exercise_id,workout_id,weight_kg,reps,is_warmup) values(u,e,w,200,20,true);
  if not exists(select 1 from sets where weight_kg=112.5 and base_weight_kg=10 and added_weight_kg=102.5) then raise exception 'snapshot'; end if;
  if not exists(select 1 from sets where weight_kg=200 and base_weight_kg=0 and added_weight_kg=200) then raise exception 'legacy total'; end if;
  result := progress_index(u);
  if (result#>>'{exercises,0,index}')::numeric <> 1.26 or result#>>'{exercises,0,days}' <> '2' then raise exception 'index: %',result; end if;
  if progress_index(u,'2026-11-01','2026-11-11')#>>'{exercises,0,days}' <> '1' then raise exception 'range'; end if;
  if progress_index(gen_random_uuid())->'exercises' <> '[]'::jsonb then raise exception 'owner'; end if;
end $$;
