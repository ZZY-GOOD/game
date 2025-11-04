-- ================================================================================
-- 修复审核批准后 status 和 is_published 字段不同步的问题
-- ================================================================================
-- 问题描述：
--   用户添加游戏被审核员审核同意后，games 表中的 status 字段仍然为 'pending'，
--   is_published 字段仍然为 false
-- 
-- 根本原因：
--   message-system-setup.sql 中的 handle_moderation_decision() 触发器在更新
--   moderation_queue 时会更新 games 表，但没有更新 is_published 字段
-- 
-- 解决方案：
--   1. 更新触发器函数，让它同时更新 is_published 字段
--   2. 创建新的触发器，确保 status 和 is_published 保持同步
--   3. 修复现有数据，将 status='approved' 的游戏设置为 is_published=true
-- ================================================================================

BEGIN;

-- ========================================
-- 第1步：确保 games 表有 is_published 字段
-- ========================================

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
    RAISE NOTICE '✓ 已添加 is_published 字段';
  ELSE
    RAISE NOTICE '✓ is_published 字段已存在';
  END IF;
END $$;

-- ========================================
-- 第2步：更新 handle_moderation_decision 触发器函数
-- ========================================

CREATE OR REPLACE FUNCTION handle_moderation_decision()
RETURNS TRIGGER AS $$
BEGIN
  -- 如果状态从 pending 变为 approved 或 rejected
  IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN
    -- 更新内容状态
    IF NEW.content_type = 'game' THEN
      -- 检查 games 表是否有 is_published 字段
      IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'games' 
        AND column_name = 'is_published'
      ) THEN
        -- 如果有 is_published 字段，同时更新它
        UPDATE public.games 
        SET status = NEW.status,
            is_published = CASE WHEN NEW.status = 'approved' THEN true ELSE false END,
            reviewed_by = NEW.moderator_id,
            reviewed_at = now(),
            rejection_reason = NEW.rejection_reason
        WHERE id = NEW.content_id;
      ELSE
        -- 如果没有 is_published 字段，只更新原有字段
        UPDATE public.games 
        SET status = NEW.status,
            reviewed_by = NEW.moderator_id,
            reviewed_at = now(),
            rejection_reason = NEW.rejection_reason
        WHERE id = NEW.content_id;
      END IF;
    ELSIF NEW.content_type = 'post' THEN
      UPDATE public.posts 
      SET status = NEW.status,
          reviewed_by = NEW.moderator_id,
          reviewed_at = now(),
          rejection_reason = NEW.rejection_reason
      WHERE id = NEW.content_id;
    END IF;
    
    -- 发送系统消息给提交者
    IF NEW.status = 'approved' THEN
      PERFORM send_system_message(
        NEW.submitter_id,
        '恭喜！您提交的' || 
        CASE NEW.content_type 
          WHEN 'game' THEN '游戏' 
          WHEN 'post' THEN '帖子' 
        END || '已通过审核并发布。',
        'moderation',
        NEW.content_type,
        NEW.content_id
      );
    ELSIF NEW.status = 'rejected' THEN
      PERFORM send_system_message(
        NEW.submitter_id,
        '很抱歉，您提交的' || 
        CASE NEW.content_type 
          WHEN 'game' THEN '游戏' 
          WHEN 'post' THEN '帖子' 
        END || '未通过审核。' ||
        CASE WHEN NEW.rejection_reason IS NOT NULL 
          THEN '原因：' || NEW.rejection_reason 
          ELSE '' 
        END,
        'moderation',
        NEW.content_type,
        NEW.content_id
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

RAISE NOTICE '✓ 已更新 handle_moderation_decision() 触发器函数';

-- ========================================
-- 第3步：创建自动同步触发器
-- ========================================

-- 创建触发器函数：当 games 表的 status 改变时，自动同步 is_published
CREATE OR REPLACE FUNCTION sync_game_publication_status()
RETURNS TRIGGER AS $$
BEGIN
  -- 当插入或更新游戏时，自动设置 is_published
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    -- 根据 status 设置 is_published
    IF NEW.status = 'approved' THEN
      NEW.is_published := true;
    ELSIF NEW.status IN ('pending', 'rejected') THEN
      NEW.is_published := false;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 删除旧触发器（如果存在）
DROP TRIGGER IF EXISTS trigger_sync_game_publication ON public.games;

-- 创建新触发器
CREATE TRIGGER trigger_sync_game_publication
  BEFORE INSERT OR UPDATE OF status ON public.games
  FOR EACH ROW
  EXECUTE FUNCTION sync_game_publication_status();

RAISE NOTICE '✓ 已创建自动同步触发器 trigger_sync_game_publication';

-- ========================================
-- 第4步：修复现有数据
-- ========================================

-- 将所有 status='approved' 但 is_published=false 的游戏设置为 is_published=true
UPDATE public.games 
SET is_published = true 
WHERE status = 'approved' 
  AND (is_published IS NULL OR is_published = false);

-- 将所有 status IN ('pending', 'rejected') 但 is_published=true 的游戏设置为 is_published=false
UPDATE public.games 
SET is_published = false 
WHERE status IN ('pending', 'rejected')
  AND is_published = true;

RAISE NOTICE '✓ 已同步现有游戏的 is_published 状态';

-- ========================================
-- 第5步：创建索引以提升查询性能
-- ========================================

CREATE INDEX IF NOT EXISTS idx_games_is_published ON public.games (is_published);
CREATE INDEX IF NOT EXISTS idx_games_status ON public.games (status);
CREATE INDEX IF NOT EXISTS idx_games_created_at ON public.games (created_at DESC);

RAISE NOTICE '✓ 已创建索引';

-- ========================================
-- 第6步：更新 RLS 策略
-- ========================================

-- 删除旧的游戏查看策略
DROP POLICY IF EXISTS "games_select_public" ON public.games;

-- 创建新的游戏查看策略
-- 所有人可以查看 is_published=true 的游戏
-- 审核员可以查看所有游戏
-- 创建者可以查看自己的游戏
CREATE POLICY "games_select_public" ON public.games
  FOR SELECT USING (
    is_published = true OR
    creator = auth.uid() OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_moderator = true)
  );

-- 确保 RLS 已启用
ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;

RAISE NOTICE '✓ 已更新 RLS 策略';

-- ========================================
-- 第7步：验证修复结果
-- ========================================

DO $$
DECLARE
  total_count INTEGER;
  published_count INTEGER;
  approved_count INTEGER;
  sync_issue_count INTEGER;
BEGIN
  -- 统计游戏数量
  SELECT COUNT(*) INTO total_count FROM public.games;
  SELECT COUNT(*) INTO published_count FROM public.games WHERE is_published = true;
  SELECT COUNT(*) INTO approved_count FROM public.games WHERE status = 'approved';
  
  -- 检查是否有不同步的记录
  SELECT COUNT(*) INTO sync_issue_count 
  FROM public.games 
  WHERE (status = 'approved' AND is_published = false)
     OR (status IN ('pending', 'rejected') AND is_published = true);
  
  RAISE NOTICE '========================================';
  RAISE NOTICE '修复完成！统计信息：';
  RAISE NOTICE '  总游戏数: %', total_count;
  RAISE NOTICE '  已发布游戏数 (is_published=true): %', published_count;
  RAISE NOTICE '  已审核通过游戏数 (status=approved): %', approved_count;
  RAISE NOTICE '  状态不同步的游戏数: %', sync_issue_count;
  RAISE NOTICE '========================================';
  
  IF sync_issue_count > 0 THEN
    RAISE WARNING '⚠ 仍有 % 条游戏的 status 和 is_published 不同步，请检查！', sync_issue_count;
  ELSE
    RAISE NOTICE '✓ 所有游戏的 status 和 is_published 已同步';
  END IF;
END $$;

-- 显示最近的游戏状态
SELECT 
  id,
  title,
  status,
  is_published,
  CASE 
    WHEN status = 'approved' AND is_published = true THEN '✓ 同步'
    WHEN status IN ('pending', 'rejected') AND is_published = false THEN '✓ 同步'
    ELSE '✗ 不同步'
  END AS sync_status,
  created_at
FROM public.games
ORDER BY created_at DESC
LIMIT 10;

COMMIT;

-- ========================================
-- 使用说明
-- ========================================

/*
1. 在 Supabase SQL Editor 中运行此脚本
2. 脚本会：
   - 确保 games 表有 is_published 字段
   - 更新触发器函数，确保审核时同步更新 is_published
   - 创建自动同步触发器，确保 status 和 is_published 始终保持一致
   - 修复现有数据，将 status='approved' 的游戏设置为 is_published=true
   - 更新 RLS 策略，确保已发布的游戏对所有人可见
3. 运行后刷新前端页面
4. 以后审核员批准游戏时，status 和 is_published 会自动保持同步

注意：
- 此脚本是幂等的，可以多次执行而不会出错
- 如果已经执行过类似的修复脚本，此脚本会覆盖之前的设置
*/

