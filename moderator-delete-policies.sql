-- 授权审核员（profiles.is_moderator = true）可删除任意游戏及其相关记录
-- 注意：RLS 已在 database.sql 中启用，这里仅补充 delete 策略

-- games 表增加审核员删除策略
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='games' AND policyname='games_delete_moderator'
  ) THEN
    EXECUTE 'create policy "games_delete_moderator" on public.games for delete using (
      EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_moderator = true)
    )';
  END IF;
END$$;

-- Storage 对象删除策略：允许审核员删除 game-gallery 桶内对象
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='storage_delete_moderator_game_gallery'
  ) THEN
    EXECUTE 'create policy "storage_delete_moderator_game_gallery" on storage.objects for delete using (
      bucket_id = ''game-gallery'' AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_moderator = true)
    )';
  END IF;
END$$;

-- game_images 表增加审核员删除策略
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='game_images' AND policyname='game_images_delete_moderator'
  ) THEN
    EXECUTE 'create policy "game_images_delete_moderator" on public.game_images for delete using (
      EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_moderator = true)
    )';
  END IF;
END$$;

-- Storage 对象删除策略：允许审核员删除 game-gallery 桶内对象
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='storage_delete_moderator_game_gallery'
  ) THEN
    EXECUTE 'create policy "storage_delete_moderator_game_gallery" on storage.objects for delete using (
      bucket_id = ''game-gallery'' AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_moderator = true)
    )';
  END IF;
END$$;

-- game_comments 表增加审核员删除策略（如需随游戏一起清理）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='game_comments' AND policyname='game_comments_delete_moderator'
  ) THEN
    EXECUTE 'create policy "game_comments_delete_moderator" on public.game_comments for delete using (
      EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_moderator = true)
    )';
  END IF;
END$$;

-- Storage 对象删除策略：允许审核员删除 game-gallery 桶内对象
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='storage_delete_moderator_game_gallery'
  ) THEN
    EXECUTE 'create policy "storage_delete_moderator_game_gallery" on storage.objects for delete using (
      bucket_id = ''game-gallery'' AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_moderator = true)
    )';
  END IF;
END$$;

-- ratings 表增加审核员删除策略（如项目有评分表）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ratings' AND policyname='ratings_delete_moderator'
  ) THEN
    EXECUTE 'create policy "ratings_delete_moderator" on public.ratings for delete using (
      EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_moderator = true)
    )';
  END IF;
END$$;

-- Storage 对象删除策略：允许审核员删除 game-gallery 桶内对象
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='storage_delete_moderator_game_gallery'
  ) THEN
    EXECUTE 'create policy "storage_delete_moderator_game_gallery" on storage.objects for delete using (
      bucket_id = ''game-gallery'' AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_moderator = true)
    )';
  END IF;
END$$;
