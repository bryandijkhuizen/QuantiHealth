begin;
create function public.correct_logged_base(p_workout uuid, p_exercise uuid, p_sets uuid[], p_base numeric, p_keep_total boolean)
returns void language plpgsql security invoker set search_path = public as $$
declare changed integer;
begin
  if auth.uid() is null or p_base is null or p_base < 0 or p_base >= 'Infinity'::numeric
    or p_keep_total is null or coalesce(cardinality(p_sets),0)=0 then raise exception 'Invalid correction'; end if;
  update sets set base_weight_kg=p_base, weight_kg=case when p_keep_total then weight_kg
    when added_weight_kg is null and p_base=0 then null else coalesce(added_weight_kg,0)+p_base end
    where user_id=auth.uid() and workout_id=p_workout and exercise_id=p_exercise and id=any(p_sets)
    and (not p_keep_total or coalesce(weight_kg,0)>=p_base);
  get diagnostics changed = row_count;
  if changed <> cardinality(p_sets) then raise exception 'Sets changed or total is below the base'; end if;
end $$;
revoke all on function public.correct_logged_base(uuid,uuid,uuid[],numeric,boolean) from public;
grant execute on function public.correct_logged_base(uuid,uuid,uuid[],numeric,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
