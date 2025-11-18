-- 帖子点赞功能初始化（幂等）
-- 创建表、唯一约束、RLS 策略与触发器，使每个用户对每个帖子最多点赞一次，并与 posts.likes 聚合计数同步

-- 1) 表结构：post_likes
CREATE TABLE IF NOT EXISTS public.post_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 2) 唯一约束：同一用户对同一帖子只能有一条记录
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'public' AND tablename = 'post_likes' AND indexname = 'uniq_post_likes_post_user'
  ) THEN
    CREATE UNIQUE INDEX uniq_post_likes_post_user ON public.post_likes(post_id, user_id);
  END IF;
END
$$ LANGUAGE plpgsql;

-- 3) 启用 RLS
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

-- 4) RLS 策略
-- 4.1 允许已登录用户读取（如不需要可改为更严格）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_likes' AND policyname = 'post_likes_select_auth'
  ) THEN
    CREATE POLICY post_likes_select_auth
      ON public.post_likes FOR SELECT
      USING (auth.role() = 'authenticated');
  END IF;
END
$$ LANGUAGE plpgsql;

-- 4.2 仅本人可插入自己的点赞记录
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_likes' AND policyname = 'post_likes_insert_self'
  ) THEN
    CREATE POLICY post_likes_insert_self
      ON public.post_likes FOR INSERT
      WITH CHECK (user_id = auth.uid());
  END IF;
END
$$ LANGUAGE plpgsql;

-- 4.3 仅本人可删除自己的点赞记录（可用于“取消点赞”，如不需要可保留以便后台管理）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_likes' AND policyname = 'post_likes_delete_self'
  ) THEN
    CREATE POLICY post_likes_delete_self
      ON public.post_likes FOR DELETE
      USING (user_id = auth.uid());
  END IF;
END
$$ LANGUAGE plpgsql;

-- 5) 触发器：同步 posts.likes 聚合计数
-- 5.1 创建函数（若不存在）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'post_likes_after_insert'
  ) THEN
    CREATE FUNCTION public.post_likes_after_insert()
    RETURNS trigger LANGUAGE plpgsql AS $fn$
    BEGIN
      UPDATE public.posts
      SET likes = COALESCE(likes, 0) + 1
      WHERE id = NEW.post_id;
      RETURN NEW;
    END;
    $fn$ SECURITY DEFINER;
  END IF;
END
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'post_likes_after_delete'
  ) THEN
    CREATE FUNCTION public.post_likes_after_delete()
    RETURNS trigger LANGUAGE plpgsql AS $fn$
    BEGIN
      UPDATE public.posts
      SET likes = GREATEST(COALESCE(likes, 0) - 1, 0)
      WHERE id = OLD.post_id;
      RETURN OLD;
    END;
    $fn$ SECURITY DEFINER;
  END IF;
END
$$ LANGUAGE plpgsql;

-- 5.2 绑定触发器（若不存在）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_post_likes_after_insert'
  ) THEN
    CREATE TRIGGER trg_post_likes_after_insert
    AFTER INSERT ON public.post_likes
    FOR EACH ROW EXECUTE FUNCTION public.post_likes_after_insert();
  END IF;
END
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_post_likes_after_delete'
  ) THEN
    CREATE TRIGGER trg_post_likes_after_delete
    AFTER DELETE ON public.post_likes
    FOR EACH ROW EXECUTE FUNCTION public.post_likes_after_delete();
  END IF;
END
$$ LANGUAGE plpgsql;

-- 6) 可选：为统计添加索引（按帖子查询点赞记录）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE schemaname = 'public' AND tablename = 'post_likes' AND indexname = 'idx_post_likes_post_id'
  ) THEN
    CREATE INDEX idx_post_likes_post_id ON public.post_likes(post_id);
  END IF;
END
$$ LANGUAGE plpgsql;
