-- 修复系统消息约束冲突（messages.related_content_type_check）
-- 问题：审核通过/拒绝时，send_system_message 使用 related_content_type='game_submission'，但
--       messages 表的 check 约束只允许 ('game','post','comment')，导致 23514。
-- 方案：扩展该约束，加入 'game_submission'，或放宽校验为允许 NULL/该值。

BEGIN;

-- 1) 删除旧的检查约束（名称可能不同，统一先删常用名）
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_related_content_type_check;

-- 2) 重建检查约束，加入 'game_submission'
ALTER TABLE public.messages
  ADD CONSTRAINT messages_related_content_type_check
  CHECK (
    related_content_type IS NULL
    OR related_content_type IN ('game','post','comment','game_submission')
  );

COMMIT;
