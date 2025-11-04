-- 评分聚合 RPC：一次性返回指定游戏的平均星级与数量
-- 使用：supabase.rpc('get_ratings_agg', { game_ids: ['uuid1','uuid2', ...] })
-- 返回列：game_id, avg, count

BEGIN;

CREATE OR REPLACE FUNCTION public.get_ratings_agg(game_ids uuid[])
RETURNS TABLE (
  game_id uuid,
  avg numeric,
  count integer
) AS $$
  SELECT r.game_id,
         AVG(r.stars)::numeric(10,4) AS avg,
         COUNT(r.stars)::int         AS count
  FROM public.ratings r
  WHERE r.game_id = ANY (game_ids)
  GROUP BY r.game_id
$$ LANGUAGE sql STABLE;

-- 允许匿名或已登录调用（按项目策略选择）。如仅登录用户可见，可改为 AUTHID 检查。
GRANT EXECUTE ON FUNCTION public.get_ratings_agg(uuid[]) TO anon, authenticated;

COMMIT;
