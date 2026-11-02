create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.user_id', true), '')::uuid $$;
do $$ begin if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$;
create table workouts(id uuid primary key default gen_random_uuid(), user_id uuid not null, created_at timestamptz default now());
create table exercises(id uuid primary key, user_id uuid, is_active boolean default true);
create table workout_exercise_blocks(id uuid primary key, workout_id uuid references workouts(id), exercise_id uuid references exercises(id), sort_order integer);
create table workout_exercise_block_order(workout_id uuid references workouts(id), exercise_block_id uuid references workout_exercise_blocks(id), sort_order integer, primary key(workout_id, exercise_block_id));
grant usage on schema public, auth to authenticated;
grant select,insert,update,delete on all tables in schema public to authenticated;
