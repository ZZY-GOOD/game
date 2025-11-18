-- 修复审核批准后 is_published 仍然为 false 的问题
-- 这个脚本会确保：
-- 1. games 表有 is_published 字段
-- 2. 审核批准时自动设置 is_published = true
-- 3. 所有已存在的游戏正确设置 is_published 状态

BEGIN;

-- ========================================
-- 第1步：确保 games 表有 is_published 字段
-- ========================================

-- 添加 is_published 字段（如果不存在）
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'games' 
    AND column_name = 'is_published'
  ) THEN
    ALTER TABLE public.games ADD COLUMN is_published boolean DEFAULT false;
    COMMENT ON COLUMN public.games.is_published IS '游戏是否已发布（审核通过后为true）';
    RAISE NOTICE '已添加 is_published 字段';
  ELSE
    RAISE NOTICE 'is_published 字段已存在';
  END IF;
END $$;

-- ========================================
-- 第2步：创建索引以提升查询性能
-- ========================================

CREATE INDEX IF NOT EXISTS idx_games_is_published ON public.games (is_published);
CREATE INDEX IF NOT EXISTS idx_games_created_at ON public.games (created_at DESC);

-- ========================================
-- 第3步：同步现有游戏的 is_published 状态
-- ========================================

-- 如果 games 表有 status 字段，将 status='approved' 的游戏设置为 is_published=true
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'games' 
    AND column_name = 'status'
  ) THEN
    UPDATE public.games 
    SET is_published = true 
    WHERE status = 'approved' 
    AND (is_published IS NULL OR is_published = false);
    
    RAISE NOTICE '已同步 status=approved 的游戏为 is_published=true';
  END IF;
END $$;

-- 如果没有 status 字段，将所有游戏都设置为已发布（根据需要调整）
-- 取消下面的注释以执行：
-- UPDATE public.games SET is_published = true WHERE is_published IS NULL OR is_published = false;

-- ========================================
-- 第4步：创建触发器，自动同步 status 和 is_published
-- ========================================

CREATE OR REPLACE FUNCTION sync_game_publication_status()
RETURNS TRIGGER AS $$
BEGIN
  -- 当插入或更新游戏时，自动设置 is_published
  
  -- 如果有 status 字段，根据 status 设置 is_published
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    -- 检查是否有 status 列
    IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'games' 
      AND column_name = 'status'
    ) THEN
      -- 有 status 字段：status='approved' -> is_published=true
      IF NEW.status = 'approved' THEN
        NEW.is_published := true;
      ELSIF NEW.status IN ('pending', 'rejected') THEN
        NEW.is_published := false;
      END IF;
    ELSE
      -- 没有 status 字段：如果 is_published 未设置，默认为 true
      IF NEW.is_published IS NULL THEN
        NEW.is_published := true;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 删除旧触发器（如果存在）
DROP TRIGGER IF EXISTS trigger_sync_game_publication ON public.games;

-- 创建新触发器
CREATE TRIGGER trigger_sync_game_publication
  BEFORE INSERT OR UPDATE ON public.games
  FOR EACH ROW
  EXECUTE FUNCTION sync_game_publication_status();

-- ========================================
-- 第5步：更新 RLS 策略
-- ========================================

-- 删除旧的游戏查看策略
DROP POLICY IF EXISTS "games_select_public" ON public.games;

-- 创建新的游戏查看策略：所有人可见 is_published=true 的游戏，审核员可见所有游戏
CREATE POLICY "games_select_public" ON public.games
  FOR SELECT USING (
    is_published = true OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_moderator = true)
  );

-- 确保 RLS 已启用
ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;

-- ========================================
-- 第6步：验证修复结果
-- ========================================

-- 显示游戏统计
SELECT 
  '修复完成！游戏统计：' AS info,
  COUNT(*) AS total_games,
  SUM(CASE WHEN is_published = true THEN 1 ELSE 0 END) AS published_games,
  SUM(CASE WHEN is_published = false OR is_published IS NULL THEN 1 ELSE 0 END) AS unpublished_games
FROM public.games;

-- 显示所有游戏的发布状态
SELECT 
  id,
  title,
  is_published,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'games' 
      AND column_name = 'status'
    ) THEN (SELECT status FROM public.games g2 WHERE g2.id = games.id)
    ELSE NULL
  END AS status,
  created_at
FROM public.games
ORDER BY created_at DESC
LIMIT 10;

COMMIT;

-- ========================================
-- 使用说明
-- ========================================

-- 1. 在 Supabase SQL Editor 中运行此脚本
-- 2. 脚本会：
--    - 添加 is_published 字段（如果不存在）
--    - 将已批准的游戏设置为 is_published = true
--    - 创建触发器，自动同步未来的游戏状态
--    - 更新 RLS 策略，允许所有人查看已发布游戏
-- 3. 运行后刷新前端页面
-- 4. 以后审核员批准游戏时，is_published 会自动设置为 true

