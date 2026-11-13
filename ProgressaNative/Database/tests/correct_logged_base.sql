begin;
create or replace function auth.uid() returns uuid language sql as $$ select current_setting('test.uid')::uuid $$;
do $$
declare u uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); w uuid:=gen_random_uuid(); s uuid:=gen_random_uuid();
begin
 perform set_config('test.uid',u::text,true);
 insert into sets(id,user_id,exercise_id,workout_id,weight_kg,reps) values(s,u,e,w,50,10);
 perform correct_logged_base(w,e,array[s],10,false);
 perform correct_logged_base(w,e,array[s],10,false);
 if not exists(select 1 from sets where id=s and weight_kg=60 and added_weight_kg=50) then raise exception 'retry'; end if;
 perform correct_logged_base(w,e,array[s],15,true);
 if not exists(select 1 from sets where id=s and weight_kg=60 and added_weight_kg=45) then raise exception 'keep total'; end if;
 begin
   perform correct_logged_base(w,e,array[s,gen_random_uuid()],25,false);
   raise exception 'partial update succeeded';
 exception when raise_exception then
   if sqlerrm <> 'Sets changed or total is below the base' then raise; end if;
 end;
 if not exists(select 1 from sets where id=s and base_weight_kg=15) then raise exception 'rollback'; end if;
end $$;
rollback;
