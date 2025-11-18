-- 帖子删除相关的 RLS 策略（作者与审核员），含存储桶 post-images 删除权限
-- 可重复执行：使用 DO $$ BEGIN ... IF NOT EXISTS ... END $$ 包裹创建策略

BEGIN;

-- 1) 启用 RLS（幂等，多次执行不报错）
ALTER TABLE IF EXISTS public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.post_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.post_comments ENABLE ROW LEVEL SECURITY;

-- 2) posts：作者可删除自己帖子
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'posts' AND policyname = 'posts_delete_owner'
  ) THEN
    CREATE POLICY posts_delete_owner ON public.posts
      FOR DELETE
      USING (author_id = auth.uid());
  END IF;
END $$ LANGUAGE plpgsql;

-- 3) posts：审核员可删除任意帖子
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'posts' AND policyname = 'posts_delete_moderator'
  ) THEN
    CREATE POLICY posts_delete_moderator ON public.posts
      FOR DELETE
      USING (EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid() AND p.is_moderator = TRUE
      ));
  END IF;
END $$ LANGUAGE plpgsql;

-- 4) post_images：作者可删除自己帖子的图片
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_images' AND policyname = 'post_images_delete_owner'
  ) THEN
    CREATE POLICY post_images_delete_owner ON public.post_images
      FOR DELETE
      USING (EXISTS (
        SELECT 1 FROM public.posts po
        WHERE po.id = post_images.post_id AND po.author_id = auth.uid()
      ));
  END IF;
END $$ LANGUAGE plpgsql;

-- 5) post_images：审核员可删除任意帖子图片记录
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_images' AND policyname = 'post_images_delete_moderator'
  ) THEN
    CREATE POLICY post_images_delete_moderator ON public.post_images
      FOR DELETE
      USING (EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid() AND p.is_moderator = TRUE
      ));
  END IF;
END $$ LANGUAGE plpgsql;

-- 6) post_comments：审核员可删除任意评论（作者删除自己评论可按需另加）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_comments' AND policyname = 'post_comments_delete_moderator'
  ) THEN
    CREATE POLICY post_comments_delete_moderator ON public.post_comments
      FOR DELETE
      USING (EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid() AND p.is_moderator = TRUE
      ));
  END IF;
END $$ LANGUAGE plpgsql;

-- 7) 存储桶 storage.objects：允许审核员删除 post-images 桶内任意对象
-- 注意：storage.objects 位于 storage 模式下
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'storage_delete_moderator_post_images'
  ) THEN
    CREATE POLICY storage_delete_moderator_post_images ON storage.objects
      FOR DELETE
      USING (
        bucket_id = 'post-images'
        AND EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND p.is_moderator = TRUE
        )
      );
  END IF;
END $$ LANGUAGE plpgsql;

COMMIT;