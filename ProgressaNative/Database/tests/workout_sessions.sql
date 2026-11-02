-- Run against a disposable database with the migration and the base schema installed.
begin;
set local role authenticated;
select set_config('test.user_id', '10000000-0000-0000-0000-000000000001', true);
insert into workouts(id,user_id,start_time) values
 ('20000000-0000-0000-0000-000000000001',auth.uid(),now());
insert into exercises(id,user_id) values
 ('30000000-0000-0000-0000-000000000001',auth.uid()),
 ('30000000-0000-0000-0000-000000000002',auth.uid()),
 ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002');
select add_workout_sequence('20000000-0000-0000-0000-000000000001',
 array['30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002']::uuid[],3);
do $$
declare n integer;
begin
 select count(*) into n from workout_exercise_blocks;
 assert n = 6, 'Three rounds must create six blocks';
 assert (select count(distinct sequence_id) from workout_exercise_blocks) = 1;
 assert (select array_agg(sequence_round order by sort_order) from workout_exercise_blocks) = array[1,1,2,2,3,3];
 assert (select count(*) from workout_exercise_block_order) = 6;
 begin
  perform add_workout_sequence('20000000-0000-0000-0000-000000000001',
    array['30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003']::uuid[],3);
  raise exception 'Expected private exercise rejection' using errcode = 'ZX001';
 exception when raise_exception then null;
 end;
 assert (select count(*) from workout_exercise_blocks) = n, 'Failure must roll back every new block';
 begin
  insert into workouts(user_id,start_time) values(auth.uid(),now());
  raise exception 'Expected active-workout uniqueness' using errcode = 'ZX001';
 exception when unique_violation then null;
 end;
 begin
  update workouts set end_time = start_time - interval '1 second';
  raise exception 'Expected invalid time rejection' using errcode = 'ZX001';
 exception when check_violation then null;
 end;
 perform set_config('test.user_id','10000000-0000-0000-0000-000000000002', true);
 begin
  perform add_workout_sequence('20000000-0000-0000-0000-000000000001',
    array['30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002']::uuid[],3);
  raise exception 'Expected foreign workout rejection' using errcode = 'ZX001';
 exception when raise_exception then null;
 end;
end $$;
rollback;
