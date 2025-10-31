-- 创建 game_submissions 草稿表、索引与 RLS 策略，并为 games 表补充发布相关字段
-- 适用于 Supabase（PostgreSQL）。可直接在 SQL Editor 执行。

BEGIN;

-- 启用 pgcrypto 扩展以便使用 gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1) 草稿表：game_submissions（普通用户提交的游戏草稿，待审核）
CREATE TABLE IF NOT EXISTS public.game_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),                -- 草稿ID
  title text NOT NULL,                                          -- 标题
  company text,                                                 -- 公司/开发商
  price numeric,                                                -- 价格
  genres text[] DEFAULT '{}',                                   -- 类型标签（文本数组）
  background text,                                              -- 背景描述
  gameplay text,                                                -- 玩法描述
  official_url text,                                            -- 官方链接
  cover_url text,                                               -- 封面图片URL
  gallery_urls jsonb DEFAULT '[]'::jsonb,                       -- 图集URL数组（JSON）
  submitter_id uuid NOT NULL,                                   -- 提交者（对应 profiles.id）
  created_at timestamptz NOT NULL DEFAULT now()                 -- 提交时间
);

-- 2) 索引（提高查询性能）
CREATE INDEX IF NOT EXISTS idx_gs_submitter_id ON public.game_submissions (submitter_id);
CREATE INDEX IF NOT EXISTS idx_gs_created_at   ON public.game_submissions (created_at DESC);

-- 3) 开启行级安全 RLS
ALTER TABLE public.game_submissions ENABLE ROW LEVEL SECURITY;

-- 4) RLS 策略
-- 4.1 提交者可读取自己的草稿
DROP POLICY IF EXISTS gs_submitter_select_own ON public.game_submissions;
CREATE POLICY gs_submitter_select_own ON public.game_submissions
FOR SELECT
USING (submitter_id = auth.uid());

-- 4.2 提交者可插入自己的草稿
DROP POLICY IF EXISTS gs_submitter_insert_own ON public.game_submissions;
CREATE POLICY gs_submitter_insert_own ON public.game_submissions
FOR INSERT
WITH CHECK (submitter_id = auth.uid());

-- 4.3 提交者可更新/删除自己的草稿
DROP POLICY IF EXISTS gs_submitter_update_own ON public.game_submissions;
CREATE POLICY gs_submitter_update_own ON public.game_submissions
FOR UPDATE
USING (submitter_id = auth.uid())
WITH CHECK (submitter_id = auth.uid());

DROP POLICY IF EXISTS gs_submitter_delete_own ON public.game_submissions;
CREATE POLICY gs_submitter_delete_own ON public.game_submissions
FOR DELETE
USING (submitter_id = auth.uid());

-- 4.4 审核员可读写全部草稿（要求 profiles.is_moderator = true）
DROP POLICY IF EXISTS gs_moderator_all_select ON public.game_submissions;
CREATE POLICY gs_moderator_all_select ON public.game_submissions
FOR SELECT
USING (EXISTS (
  SELECT 1 FROM public.profiles p
  WHERE p.id = auth.uid() AND COALESCE(p.is_moderator,false) = true
));

DROP POLICY IF EXISTS gs_moderator_all_update ON public.game_submissions;
CREATE POLICY gs_moderator_all_update ON public.game_submissions
FOR UPDATE
USING (EXISTS (
  SELECT 1 FROM public.profiles p
  WHERE p.id = auth.uid() AND COALESCE(p.is_moderator,false) = true
))
WITH CHECK (EXISTS (
  SELECT 1 FROM public.profiles p
  WHERE p.id = auth.uid() AND COALESCE(p.is_moderator,false) = true
));

DROP POLICY IF EXISTS gs_moderator_all_delete ON public.game_submissions;
CREATE POLICY gs_moderator_all_delete ON public.game_submissions
FOR DELETE
USING (EXISTS (
  SELECT 1 FROM public.profiles p
  WHERE p.id = auth.uid() AND COALESCE(p.is_moderator,false) = true
));

-- 5) 为 games 表补充发布相关字段（若不存在则创建）
ALTER TABLE public.games ADD COLUMN IF NOT EXISTS is_published boolean NOT NULL DEFAULT false; -- 是否已发布/审核通过
ALTER TABLE public.games ADD COLUMN IF NOT EXISTS reviewed_at timestamptz NULL;                -- 审核通过时间
ALTER TABLE public.games ADD COLUMN IF NOT EXISTS rejection_reason text NULL;                  -- 拒绝原因（如需保留在正式表）

-- 6) games 常用索引（前台列表更快）
CREATE INDEX IF NOT EXISTS idx_games_is_published ON public.games (is_published);
CREATE INDEX IF NOT EXISTS idx_games_created_at   ON public.games (created_at DESC);

COMMIT;

-- 备注：
-- 1) 如果 profiles 表尚无 is_moderator 字段，请先创建：
--    ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_moderator boolean NOT NULL DEFAULT false;
-- 2) 审核流程：用户提交数据进入 game_submissions；审核通过后拷贝至 games 并置 is_published=true；
--    拒绝则保持草稿或后续清理；moderation_queue 记录流程状态。