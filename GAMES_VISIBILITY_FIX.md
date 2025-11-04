# 游戏可见性问题修复指南

## 问题描述

当前存在的问题：
- ❌ 普通用户只能看到自己发布的游戏
- ❌ 审核员可以看到所有用户发布的游戏
- ❌ 其他用户看不到已发布的游戏

## 期望的行为

修复后的行为：
- ✅ 所有人都能看到已发布（`is_published = true`）的游戏
- ✅ 审核员可以看到所有游戏（包括未发布的）
- ✅ 普通用户可以看到自己未发布的游戏（在个人中心）

## 问题根源

数据库的 RLS（Row Level Security）策略使用了 `status` 字段来控制游戏可见性，但前端代码使用的是 `is_published` 字段，导致字段不匹配。

旧的 RLS 策略：
```sql
-- 只有 status = 'approved' 的游戏对所有人可见
CREATE POLICY "games_select_public" ON public.games
  FOR SELECT USING (
    status = 'approved' OR 
    creator = auth.uid() OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_moderator = true)
  );
```

## 修复步骤

### 步骤 1：运行修复脚本

1. 登录 [Supabase Dashboard](https://supabase.com/dashboard)
2. 选择你的项目
3. 点击左侧菜单的 **SQL Editor**
4. 创建一个新查询
5. 复制 `fix-games-visibility.sql` 文件的全部内容
6. 粘贴到 SQL Editor 中
7. 点击 **Run** 按钮执行

### 步骤 2：验证修复

执行脚本后，你会看到类似这样的输出：

```
status          | total_games | published_games | unpublished_games
修复完成！      | 22          | 22              | 0
```

### 步骤 3：刷新前端

1. 在浏览器中打开你的游戏网站
2. 清除浏览器缓存或按 `Ctrl + Shift + R`（Windows）/ `Cmd + Shift + R`（Mac）
3. 重新登录（如果已登录，先退出再登录）
4. 现在应该能看到所有已发布的游戏了

## 新的 RLS 策略

修复后的策略：

```sql
CREATE POLICY "games_select_public" ON public.games
  FOR SELECT USING (
    is_published = true OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_moderator = true)
  );
```

这个策略的逻辑：
1. ✅ **所有人**（包括未登录用户）可以看到 `is_published = true` 的游戏
2. ✅ **审核员**可以看到所有游戏（包括 `is_published = false` 的游戏）

## 自动同步机制

修复脚本还创建了一个触发器，自动同步 `status` 和 `is_published` 字段：

- 当游戏的 `status` 改为 `'approved'` 时，自动设置 `is_published = true`
- 当游戏的 `status` 不是 `'approved'` 时，自动设置 `is_published = false`

## 测试验证

### 测试 1：普通用户可见性

1. 以普通用户身份登录
2. 访问游戏目录页面
3. ✅ 应该能看到所有已发布的游戏（不仅仅是自己发布的）

### 测试 2：审核员可见性

1. 以审核员身份登录
2. 访问游戏目录页面
3. ✅ 应该能看到所有游戏
4. 访问审核管理页面
5. ✅ 应该能看到待审核的游戏提交

### 测试 3：未登录用户可见性

1. 退出登录
2. 访问游戏目录页面
3. ✅ 应该能看到所有已发布的游戏

## 常见问题

### Q1: 运行脚本后还是只能看到自己的游戏？

**解决方法：**
1. 检查游戏的 `is_published` 字段是否为 `true`
2. 在 Supabase SQL Editor 中运行：
```sql
SELECT id, title, is_published, status FROM public.games;
```
3. 如果 `is_published` 都是 `false`，手动更新：
```sql
UPDATE public.games SET is_published = true;
```

### Q2: 如何设置审核员？

在 Supabase SQL Editor 中运行：
```sql
-- 替换 'your-user-email@example.com' 为实际的邮箱
UPDATE public.profiles 
SET is_moderator = true 
WHERE id = (
  SELECT id FROM auth.users WHERE email = 'your-user-email@example.com'
);
```

### Q3: 如何查看当前的 RLS 策略？

```sql
SELECT 
  schemaname,
  tablename,
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'games';
```

## 回滚（如果需要）

如果需要恢复到旧的策略：

```sql
BEGIN;

-- 删除新策略
DROP POLICY IF EXISTS "games_select_public" ON public.games;

-- 恢复旧策略
CREATE POLICY "games_select_public" ON public.games
  FOR SELECT USING (
    status = 'approved' OR 
    creator = auth.uid() OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_moderator = true)
  );

COMMIT;
```

## 总结

修复后：
- ✅ 所有用户都能看到已发布的游戏
- ✅ 审核员拥有审核和管理游戏的权限
- ✅ 游戏可见性逻辑更加合理
- ✅ 自动同步 `status` 和 `is_published` 字段

如有问题，请检查 Supabase 日志或联系技术支持。

