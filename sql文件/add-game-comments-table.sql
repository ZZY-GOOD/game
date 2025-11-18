-- add-game-comments-table.sql
-- 目的：
-- 1) 新增游戏评论表 public.game_comments，用于存储“游戏详情页”的评论数据
-- 2) 将原有帖子评论表 public.comments 重命名为 public.post_comments，以便与游戏评论区分
-- 3) 同步索引与 RLS 策略
-- 注意：如项目已上线并有数据，请先备份数据并在维护窗口执行。

-- 1. 重命名帖子评论表：comments -> post_comments
--    若环境中不存在 comments 表或已改名，请忽略该步骤（加 IF EXISTS 保护）
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'comments'
  ) THEN
    EXECUTE 'alter table public.comments rename to post_comments';
  END IF;
END$$;

-- 1.1 调整依赖索引名字（可选）
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'idx_comments_post_id_created_at') THEN
    EXECUTE 'alter index public.idx_comments_post_id_created_at rename to idx_post_comments_post_id_created_at';
  END IF;
END$$;

-- 2. 创建游戏评论表（如不存在）
create table if not exists public.game_comments (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  author_id uuid references public.profiles(id) on delete set null,
  author_name text,
  content text not null,
  rating int check (rating between 1 and 5),
  created_at timestamptz default now()
);

-- 2.1 索引
create index if not exists idx_game_comments_game_id_created_at on public.game_comments(game_id, created_at desc);

-- 3. 为新旧评论表开启 RLS
alter table if exists public.post_comments enable row level security;
alter table if exists public.game_comments enable row level security;

-- 3.1 帖子评论 RLS（与之前 comments 策略一致）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_comments' AND policyname='post_comments_select_public'
  ) THEN
    EXECUTE 'create policy "post_comments_select_public" on public.post_comments for select using (true)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_comments' AND policyname='post_comments_insert_auth'
  ) THEN
    EXECUTE 'create policy "post_comments_insert_auth" on public.post_comments for insert with check (auth.role() = ''authenticated'')';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_comments' AND policyname='post_comments_update_owner'
  ) THEN
    EXECUTE 'create policy "post_comments_update_owner" on public.post_comments for update using (author_id = auth.uid())';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_comments' AND policyname='post_comments_delete_owner'
  ) THEN
    EXECUTE 'create policy "post_comments_delete_owner" on public.post_comments for delete using (author_id = auth.uid())';
  END IF;
END$$;

-- 3.2 游戏评论 RLS
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='game_comments' AND policyname='game_comments_select_public'
  ) THEN
    EXECUTE 'create policy "game_comments_select_public" on public.game_comments for select using (true)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='game_comments' AND policyname='game_comments_insert_auth'
  ) THEN
    EXECUTE 'create policy "game_comments_insert_auth" on public.game_comments for insert with check (auth.role() = ''authenticated'')';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='game_comments' AND policyname='game_comments_update_owner'
  ) THEN
    EXECUTE 'create policy "game_comments_update_owner" on public.game_comments for update using (author_id = auth.uid())';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='game_comments' AND policyname='game_comments_delete_owner'
  ) THEN
    EXECUTE 'create policy "game_comments_delete_owner" on public.game_comments for delete using (author_id = auth.uid())';
  END IF;
END$$;

-- 4. 视图/连带（无）
--    若你有触发器或外键指向 public.comments，请一并迁移到 public.post_comments。

-- 5. 数据迁移（可选）：若需要将旧 comments 数据迁移到 post_comments（若已重命名则无需操作）
--    本脚本采用重命名方式，无需拷贝数据。

-- 执行指引：
-- 1) 在 Supabase SQL Editor 或 psql 中执行本文件全部语句。
-- 2) 如生产库存在策略/触发器差异，请据实际情况微调。
-- 3) 前端代码已替换为使用表名 post_comments（帖子）与 game_comments（游戏）。
