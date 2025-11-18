-- ==========================================
-- 修复审核拒绝游戏时的消息错误
-- ==========================================
-- 问题：审核员拒绝游戏时，控制台报错：
--   null value in column "content" of relation "messages" 
--   violates not-null constraint
-- 
-- 原因：
-- 1. 触发器函数 handle_moderation_decision() 在处理 'game_submission' 
--    类型时，CASE 语句没有匹配项，导致 content 为 NULL
-- 2. messages 表的 related_content_type 约束可能不包含 'game_submission'
--
-- 解决方案：
-- 1. 更新触发器函数，支持 'game_submission' 类型
-- 2. 更新 messages 表约束，允许 'game_submission'
-- 3. 更新 moderation_queue 表约束，允许 'game_submission'
-- ==========================================

BEGIN;

-- ==========================================
-- 第一步：确保依赖
-- ==========================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 确保 profiles 表有 is_moderator 字段
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_moderator boolean NOT NULL DEFAULT false;

-- ==========================================
-- 第二步：修复 moderation_queue 表约束
-- ==========================================
ALTER TABLE public.moderation_queue
  DROP CONSTRAINT IF EXISTS moderation_queue_content_type_check;

ALTER TABLE public.moderation_queue
  ADD CONSTRAINT moderation_queue_content_type_check
  CHECK (content_type IN ('game_submission', 'game', 'post'));

-- ==========================================
-- 第三步：修复 messages 表约束
-- ==========================================
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_related_content_type_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_related_content_type_check
  CHECK (
    related_content_type IS NULL
    OR related_content_type IN ('game', 'post', 'comment', 'game_submission')
  );

-- ==========================================
-- 第四步：更新触发器函数
-- ==========================================
CREATE OR REPLACE FUNCTION handle_moderation_decision()
RETURNS TRIGGER AS $$
BEGIN
  -- 仅当状态从 pending 变为 approved 或 rejected 时处理
  IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN
    
    -- 更新内容状态（仅针对 game 和 post 类型）
    -- game_submission 类型由前端在审核通过时处理迁移
    IF NEW.content_type = 'game' THEN
      UPDATE public.games 
      SET status = NEW.status,
          reviewed_by = NEW.moderator_id,
          reviewed_at = now(),
          rejection_reason = NEW.rejection_reason
      WHERE id = NEW.content_id;
    ELSIF NEW.content_type = 'post' THEN
      UPDATE public.posts 
      SET status = NEW.status,
          reviewed_by = NEW.moderator_id,
          reviewed_at = now(),
          rejection_reason = NEW.rejection_reason
      WHERE id = NEW.content_id;
    END IF;
    
    -- 发送系统消息给提交者
    -- 使用 COALESCE 确保 content 不为 NULL
    IF NEW.status = 'approved' THEN
      PERFORM send_system_message(
        NEW.submitter_id,
        '恭喜！您提交的' || 
        COALESCE(
          CASE NEW.content_type 
            WHEN 'game' THEN '游戏'
            WHEN 'game_submission' THEN '游戏'
            WHEN 'post' THEN '帖子'
            ELSE '内容'
          END,
          '内容'
        ) || '已通过审核并发布。',
        'moderation',
        NEW.content_type,
        NEW.content_id
      );
    ELSIF NEW.status = 'rejected' THEN
      PERFORM send_system_message(
        NEW.submitter_id,
        '很抱歉，您提交的' || 
        COALESCE(
          CASE NEW.content_type 
            WHEN 'game' THEN '游戏'
            WHEN 'game_submission' THEN '游戏'
            WHEN 'post' THEN '帖子'
            ELSE '内容'
          END,
          '内容'
        ) || '未通过审核。' ||
        CASE 
          WHEN NEW.rejection_reason IS NOT NULL AND NEW.rejection_reason != '' 
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
$$ LANGUAGE plpgsql;

-- ==========================================
-- 第五步：重新创建触发器
-- ==========================================
DROP TRIGGER IF EXISTS moderation_decision_trigger ON public.moderation_queue;
CREATE TRIGGER moderation_decision_trigger
  AFTER UPDATE ON public.moderation_queue
  FOR EACH ROW
  EXECUTE FUNCTION handle_moderation_decision();

-- ==========================================
-- 第六步：确保 RLS 策略正确
-- ==========================================
ALTER TABLE public.moderation_queue ENABLE ROW LEVEL SECURITY;

-- 允许普通用户插入自己的待审核记录
DROP POLICY IF EXISTS mq_insert_submitter ON public.moderation_queue;
CREATE POLICY mq_insert_submitter ON public.moderation_queue
FOR INSERT
WITH CHECK (
  submitter_id = auth.uid()
  AND status = 'pending'
  AND content_type IN ('game_submission', 'game', 'post')
);

-- 允许提交者和审核员查看审核队列
DROP POLICY IF EXISTS moderation_queue_select_moderators ON public.moderation_queue;
CREATE POLICY moderation_queue_select_moderators ON public.moderation_queue
FOR SELECT
USING (
  submitter_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND COALESCE(p.is_moderator, false) = true
  )
);

-- 允许审核员更新审核队列
DROP POLICY IF EXISTS moderation_queue_update_moderators ON public.moderation_queue;
CREATE POLICY moderation_queue_update_moderators ON public.moderation_queue
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND COALESCE(p.is_moderator, false) = true
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND COALESCE(p.is_moderator, false) = true
  )
);

-- ==========================================
-- 第七步：创建有用的索引
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_mq_status_created_at ON public.moderation_queue (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mq_content_type ON public.moderation_queue (content_type);
CREATE INDEX IF NOT EXISTS idx_mq_submitter_id ON public.moderation_queue (submitter_id);
CREATE INDEX IF NOT EXISTS idx_profiles_moderator ON public.profiles (is_moderator) WHERE is_moderator = true;

COMMIT;

-- ==========================================
-- 执行结果验证
-- ==========================================
SELECT 'fix-rejection-message-error.sql 执行成功！' as status;
SELECT '现在审核员拒绝游戏时应该不会再报错了。' as message;

-- ==========================================
-- 使用说明
-- ==========================================
-- 1. 在 Supabase Dashboard 的 SQL Editor 中执行此脚本
-- 2. 执行成功后，审核员拒绝游戏时将正确发送系统消息
-- 3. 不会再出现 "null value in column content" 错误
-- ==========================================

