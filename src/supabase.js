import { createClient } from '@supabase/supabase-js'

// 请替换为你的Supabase项目配置
// 获取方式：登录Supabase控制台 → 选择项目 → Settings → API
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  console.error('[Supabase] 缺少环境变量 VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY，请在部署环境中配置。当前值：', {
    VITE_SUPABASE_URL: supabaseUrl,
    VITE_SUPABASE_ANON_KEY: supabaseAnonKey ? '***' : undefined
  });
}

// 创建Supabase客户端（若变量缺失，会导致请求失败并在控制台给出明确错误）
export const supabase = createClient(supabaseUrl || '', supabaseAnonKey || '')

export default supabase