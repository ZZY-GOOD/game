-- ==========================================
-- 修复审核员无法插入游戏图集的问题
-- ==========================================
-- 问题：审核员审核通过游戏时，向 game_images 表插入图片失败
-- 错误：new row violates row-level security policy for table "game_images"
-- 原因：RLS 策略只允许游戏创建者插入图片，不允许审核员插入
-- 解决：添加策略允许审核员插入 game_images
-- ==========================================

BEGIN;

-- 删除旧的策略（如果需要重建）
DROP POLICY IF EXISTS "game_images_mutation_owner" ON public.game_images;

-- 创建新的插入策略：允许游戏创建者和审核员插入
CREATE POLICY "game_images_insert_owner_or_moderator" ON public.game_images
FOR INSERT
WITH CHECK (
  -- 游戏创建者可以插入
  EXISTS (
    SELECT 1 FROM public.games g 
    WHERE g.id = game_images.game_id AND g.creator = auth.uid()
  )
  OR
  -- 审核员可以插入
  EXISTS (
    SELECT 1 FROM public.profiles p 
    WHERE p.id = auth.uid() AND COALESCE(p.is_moderator, false) = true
  )
);

-- 创建更新策略：只允许游戏创建者更新
CREATE POLICY "game_images_update_owner" ON public.game_images
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.games g 
    WHERE g.id = game_images.game_id AND g.creator = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.games g 
    WHERE g.id = game_images.game_id AND g.creator = auth.uid()
  )
);

-- 创建删除策略：允许游戏创建者和审核员删除
CREATE POLICY "game_images_delete_owner_or_moderator" ON public.game_images
FOR DELETE
USING (
  -- 游戏创建者可以删除
  EXISTS (
    SELECT 1 FROM public.games g 
    WHERE g.id = game_images.game_id AND g.creator = auth.uid()
  )
  OR
  -- 审核员可以删除
  EXISTS (
    SELECT 1 FROM public.profiles p 
    WHERE p.id = auth.uid() AND COALESCE(p.is_moderator, false) = true
  )
);

COMMIT;

SELECT 'game_images RLS 策略已修复，审核员现在可以插入游戏图集了。' as status;

