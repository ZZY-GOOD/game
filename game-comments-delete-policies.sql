-- 游戏评论删除策略（作者与审核员）
-- 说明：在 Supabase SQL Editor 中执行本文件。已包含幂等检查，可多次执行。

-- 1) 启用 RLS
ALTER TABLE public.game_comments ENABLE ROW LEVEL SECURITY;

-- 2) 作者可删除自己的评论
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'game_comments'
      AND policyname = 'game_comments_delete_owner'
  ) THEN
    CREATE POLICY game_comments_delete_owner
      ON public.game_comments
      FOR DELETE
      USING (author_id = auth.uid());
  END IF;
END
$$ LANGUAGE plpgsql;

-- 3) 审核员可删除所有评论
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'game_comments'
      AND policyname = 'game_comments_delete_moderator'
  ) THEN
    CREATE POLICY game_comments_delete_moderator
      ON public.game_comments
      FOR DELETE
      USING (
        EXISTS (
          SELECT 1
          FROM public.profiles p
          WHERE p.id = auth.uid()
            AND p.is_moderator = TRUE
        )
      );
  END IF;
END
$$ LANGUAGE plpgsql;
