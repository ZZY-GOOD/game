-- 修复游戏可见性问题
-- 目标：所有人都能看到已发布的游戏，审核员可以看到所有游戏（包括未发布的）

BEGIN;

-- 1. 删除旧的游戏查看策略
DROP POLICY IF EXISTS "games_select_public" ON public.games;

-- 2. 创建新的游戏查看策略
-- 允许所有人查看 is_published = true 的游戏
-- 审核员可以查看所有游戏
CREATE POLICY "games_select_public" ON public.games
  FOR SELECT USING (
    is_published = true OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_moderator = true)
  );

-- 3. 确保 games 表有 is_published 字段（如果没有则添加）
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
  END IF;
END $$;

-- 4. 如果游戏表使用 status 字段，同步 is_published 状态
-- 将 status = 'approved' 的游戏设置为 is_published = true
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'games' 
    AND column_name = 'status'
  ) THEN
    UPDATE public.games SET is_published = true WHERE status = 'approved' AND is_published IS DISTINCT FROM true;
  END IF;
END $$;

-- 5. 创建触发器，自动同步 status 和 is_published
CREATE OR REPLACE FUNCTION sync_game_publication_status()
RETURNS TRIGGER AS $$
BEGIN
  -- 当 status 改为 'approved' 时，自动设置 is_published = true
  IF NEW.status = 'approved' AND (OLD.status IS DISTINCT FROM 'approved' OR OLD.is_published IS DISTINCT FROM true) THEN
    NEW.is_published := true;
  END IF;
  
  -- 当 status 不是 'approved' 时，设置 is_published = false
  IF NEW.status IS DISTINCT FROM 'approved' AND NEW.is_published = true THEN
    NEW.is_published := false;
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

-- 6. 验证修复结果
SELECT 
  '修复完成！' AS status,
  COUNT(*) AS total_games,
  SUM(CASE WHEN is_published = true THEN 1 ELSE 0 END) AS published_games,
  SUM(CASE WHEN is_published = false OR is_published IS NULL THEN 1 ELSE 0 END) AS unpublished_games
FROM public.games;

-- 显示当前策略
SELECT 
  'Current policies for games table:' AS info,
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'games';

COMMIT;

-- 使用说明：
-- 1. 在 Supabase SQL Editor 中运行此脚本
-- 2. 运行完成后，刷新前端页面
-- 3. 现在所有用户都能看到 is_published = true 的游戏
-- 4. 审核员可以看到所有游戏（包括未发布的）

