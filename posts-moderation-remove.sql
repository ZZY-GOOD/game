-- 目的：取消“发帖需要审核”的设计，让帖子发布后立即对所有人可见
-- 使用说明：
-- 1) 在 Supabase SQL 编辑器执行本脚本；可重复执行（幂等）。
-- 2) 本脚本仅影响 posts 的可见策略与审核相关字段，不影响游戏审核等其他功能。

-- 一、放宽帖子读取策略（RLS）——所有用户均可读取帖子
DO $$
BEGIN
  -- 如果已存在旧的按状态控制的可见策略，则移除
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname='public' AND tablename='posts' AND policyname='posts_select_public'
  ) THEN
    EXECUTE 'DROP POLICY "posts_select_public" ON public.posts';
  END IF;
END$$;

-- 重新创建“公开读取”策略
CREATE POLICY IF NOT EXISTS posts_select_public ON public.posts
  FOR SELECT USING (true);

-- 二、移除 posts 表中与“审核”相关的字段（若存在则删除）
-- 提示：如有依赖这些字段的视图/触发器/外键，请先移除依赖后再执行
ALTER TABLE public.posts DROP COLUMN IF EXISTS status;
ALTER TABLE public.posts DROP COLUMN IF EXISTS reviewed_by;
ALTER TABLE public.posts DROP COLUMN IF EXISTS reviewed_at;
ALTER TABLE public.posts DROP COLUMN IF EXISTS rejection_reason;

-- 三、删除与状态相关的索引（如果存在）
DROP INDEX IF EXISTS idx_posts_status;

-- 完成：
-- - 帖子将不再依赖审核状态即可被所有人读取
-- - 发帖时无需写入任何审核状态字段
-- - 若需要彻底移除“帖子审核”前端页面入口，请告知，我可继续清理前端路由与组件
