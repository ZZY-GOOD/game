-- 审核队列与审核消息修复脚本（适用于 Supabase / PostgreSQL）
-- 目标：
-- 1) 允许 content_type 包含 'game_submission'
-- 2) 为普通用户放行插入审核队列的 RLS 策略（仅限提交本人、且为 pending）
-- 3) 修复 handle_moderation_decision() 使其兼容 'game_submission'，并避免系统消息 content 为空导致 23502 错误
-- 4)（可选）补充索引；确保 profiles 表存在 is_moderator 字段

BEGIN;

-- 0) 依赖扩展（若尚未启用）
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1) 确保 profiles 表存在 is_moderator 字段（审核员标记）
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_moderator boolean NOT NULL DEFAULT false;

-- 2) 审核队列 content_type 检查约束：加入 'game_submission'
-- 如果约束已存在，先删除后重建
ALTER TABLE public.moderation_queue
  DROP CONSTRAINT IF EXISTS moderation_queue_content_type_check;

ALTER TABLE public.moderation_queue
  ADD CONSTRAINT moderation_queue_content_type_check
  CHECK (content_type IN ('game_submission','game','post'));

-- 3)（可选）补充常用索引
CREATE INDEX IF NOT EXISTS idx_mq_status_created_at ON public.moderation_queue (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mq_content_type      ON public.moderation_queue (content_type);
CREATE INDEX IF NOT EXISTS idx_mq_submitter_id      ON public.moderation_queue (submitter_id);

-- 4) 开启 RLS（若未开启）
ALTER TABLE public.moderation_queue ENABLE ROW LEVEL SECURITY;

-- 5) RLS 策略
-- 5.1 普通登录用户：允许插入“自己的 pending 记录”（用于把草稿加入审核队列）
DROP POLICY IF EXISTS mq_insert_submitter ON public.moderation_queue;
CREATE POLICY mq_insert_submitter ON public.moderation_queue
FOR INSERT
WITH CHECK (
  submitter_id = auth.uid()
  AND status = 'pending'
  AND content_type IN ('game_submission','game','post')
);

-- 5.2 审核员：允许查询审核队列
DROP POLICY IF EXISTS moderation_queue_select_moderators ON public.moderation_queue;
CREATE POLICY moderation_queue_select_moderators ON public.moderation_queue
FOR SELECT
USING (
  submitter_id = auth.uid() -- 提交者可见自身记录
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND COALESCE(p.is_moderator,false) = true
  )
);

-- 5.3 审核员：允许更新状态（通过/拒绝）
DROP POLICY IF EXISTS moderation_queue_update_moderators ON public.moderation_queue;
CREATE POLICY moderation_queue_update_moderators ON public.moderation_queue
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND COALESCE(p.is_moderator,false) = true
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND COALESCE(p.is_moderator,false) = true
  )
);

-- 6) 修复审核通过/拒绝触发器函数（兼容 game_submission，且使用 COALESCE 防止 content 为空）
CREATE OR REPLACE FUNCTION handle_moderation_decision()
RETURNS TRIGGER AS $$
BEGIN
  -- 仅当 pending -> approved/rejected 时处理
  IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN

    -- 可选：仅对 game/post 写回状态；game_submission 由前端迁移已完成
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

    -- 统一生成系统消息内容（兼容 game_submission；避免 NULL 拼接）
    PERFORM send_system_message(
      NEW.submitter_id,
      CASE
        WHEN NEW.status = 'approved' THEN
          '恭喜！您提交的' ||
          COALESCE(
            CASE NEW.content_type
              WHEN 'game_submission' THEN '游戏'
              WHEN 'game' THEN '游戏'
              WHEN 'post' THEN '帖子'
              ELSE '内容'
            END,
            '内容'
          ) || '已通过审核并发布。'
        ELSE
          '很抱歉，您提交的' ||
          COALESCE(
            CASE NEW.content_type
              WHEN 'game_submission' THEN '游戏'
              WHEN 'game' THEN '游戏'
              WHEN 'post' THEN '帖子'
              ELSE '内容'
            END,
            '内容'
          ) || '未通过审核。' || COALESCE('原因：' || NEW.rejection_reason, '')
      END,
      'moderation',
      NEW.content_type,
      NEW.content_id
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7) 重新绑定触发器（若已存在则替换）
DROP TRIGGER IF EXISTS moderation_decision_trigger ON public.moderation_queue;
CREATE TRIGGER moderation_decision_trigger
  AFTER UPDATE ON public.moderation_queue
  FOR EACH ROW
  EXECUTE FUNCTION handle_moderation_decision();

COMMIT;

-- 使用说明：
-- 1) 在 Supabase SQL Editor 中直接运行本脚本。
-- 2) 运行成功后，普通用户提交草稿应能成功加入审核队列（content_type='game_submission'）。
-- 3) 审核员在前端通过后，将不再出现 messages.content 为空导致的 23502 错误。
-- 4) 前端列表只展示 games.is_published = true 的游戏；审核通过时已由前端迁移草稿至 games 并设为 true。