import { reactive, watch } from 'vue';
import { supabase } from './supabase.js';

const STORAGE_KEY = 'game_forum_store_v1';

function load() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function save(state) {
  try {
    // 创建一个轻量级的状态副本，移除大型数据
    const lightState = {
      ...state,
      games: state.games.map(game => ({
        ...game,
        // 如果图片是 base64 数据，则不保存到 localStorage
        cover: game.cover && game.cover.startsWith('data:') ? '' : game.cover,
        gallery: game.gallery ? game.gallery.filter(img => !img.startsWith('data:')) : []
      })),
      posts: state.posts.map(post => ({
        ...post,
        // 移除 base64 图片数据
        images: post.images ? post.images.filter(img => !img.startsWith('data:')) : []
      }))
    };
    
    localStorage.setItem(STORAGE_KEY, JSON.stringify(lightState));
  } catch (error) {
    console.warn('保存到 localStorage 失败:', error);
    // 如果仍然失败，尝试只保存基本信息
    try {
      const minimalState = {
        user: state.user,
        profiles: state.profiles,
        relations: state.relations,
        searchGame: state.searchGame,
        searchForum: state.searchForum,
        games: state.games.map(g => ({
          id: g.id,
          title: g.title,
          company: g.company,
          price: g.price,
          genres: g.genres,
          creator: g.creator,
          createdAt: g.createdAt,
          supabase_id: g.supabase_id
        })),
        posts: state.posts.map(p => ({
          id: p.id,
          title: p.title,
          author: p.author,
          content: p.content,
          likes: p.likes,
          createdAt: p.createdAt,
          supabase_id: p.supabase_id
        }))
      };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(minimalState));
    } catch (finalError) {
      console.error('无法保存到 localStorage，清除旧数据:', finalError);
      localStorage.removeItem(STORAGE_KEY);
    }
  }
}

function newId(prefix) {
  return prefix + '_' + Math.random().toString(36).slice(2, 10);
}

function parseGallery(g) {
  if (!g) return [];
  if (Array.isArray(g)) return g.filter(Boolean);
  return String(g).split(',').map(s => s.trim()).filter(Boolean);
}

function parseGenres(genres, fallback) {
  if (!genres && fallback) return [fallback].filter(Boolean);
  if (Array.isArray(genres)) return genres.filter(Boolean);
  const s = String(genres || '').trim();
  return s ? [s] : [];
}

const defaultState = {
  user: null,
  /* 用户资料与关系 */
  profiles: {},           /* { [name]: { avatar?: string } } */
  relations: {},          /* { [name]: { followers: string[], following: string[] } } */
  /* 全局搜索 */
  searchGame: '',
  searchForum: '',
  games: [
    {
      id: 'game_demo',
      title: '示例游戏：永夜传说',
      company: '星环工作室',
      price: 128,
      genre: '角色扮演',
      genres: ['角色扮演'],
      background: '在永夜笼罩的大陆，玩家踏上寻找曙光的旅途。',
      gameplay: '开放世界探索 + 回合制战斗 + 队伍养成。',
      officialUrl: 'https://example.com/demo-game',
      cover: '',
      gallery: [
        'https://picsum.photos/seed/game1/1200/600',
        'https://picsum.photos/seed/game2/1200/600',
        'https://picsum.photos/seed/game3/1200/600'
      ],
      createdAt: Date.now(),
      ratings: [], // 每条：{ userId, rating(1-5), createdAt }
      comments: [] // 每条：{ id, author, content, rating, createdAt, likes }
    }
  ],
  posts: [
    {
      id: 'post_demo',
      title: '新人报道：永夜传说初体验',
      author: '小明',
      content: '战斗节奏不错，剧情也挺吸引人。你们都玩到哪了？',
      createdAt: Date.now(),
      likes: 3,
      comments: [
        { id: newId('c'), author: '路人甲', content: '刚打完第一章 Boss！', createdAt: Date.now() }
      ]
    }
  ]
};

/* 数据迁移：兼容旧结构并兜底缺失字段 */
function migrate(data) {
  const base = JSON.parse(JSON.stringify(defaultState));
  const src = data && typeof data === 'object' ? data : {};
  base.user = src.user ?? base.user;

  base.games = Array.isArray(src.games) ? src.games : base.games;
  // 过滤掉本地占位或未写入数据库的游戏
  base.games = (base.games || []).filter(g => !!g.supabase_id);
  base.posts = Array.isArray(src.posts) ? src.posts.map(post => ({
    ...post,
    comments: Array.isArray(post.comments) ? post.comments : [],
    images: Array.isArray(post.images) ? post.images : []
  })) : base.posts;

  base.profiles = src.profiles && typeof src.profiles === 'object' ? src.profiles : {};
  base.relations = src.relations && typeof src.relations === 'object' ? src.relations : {};

  base.games = base.games.map(g => ({
    ...g,
    gallery: parseGallery(g.gallery),
    genres: parseGenres(g.genres, g.genre?.trim() || '未分类')
  }));
  base.posts = base.posts.map(p => ({
    ...p,
    images: Array.isArray(p.images) ? p.images : [],
    comments: Array.isArray(p.comments) ? p.comments : []
  }));
  return base;
}

const persisted = load();
export const store = reactive(migrate(persisted));

watch(store, (s) => save(s), { deep: true });

// 从 Supabase 加载数据
export async function loadDataFromSupabase() {
  try {
    console.log('开始从 Supabase 加载数据...');
    
    // 加载游戏数据（包含图集）
    const { data: gamesData, error: gamesError } = await supabase
      .from('games')
      .select(`
        *,
        profiles:creator(name, avatar_url),
        game_images(image_url, position)
      `)
      .order('created_at', { ascending: false });
    
    if (gamesError) {
      console.error('加载游戏数据失败:', gamesError);
    } else if (gamesData && gamesData.length > 0) {
      // 转换 Supabase 数据格式为本地格式
      const convertedGames = gamesData.map(game => {
        // 处理图集数据
        const gallery = game.game_images 
          ? game.game_images
              .sort((a, b) => a.position - b.position) // 按位置排序
              .map(img => img.image_url)
          : [];
        
        return {
          id: game.id,
          title: game.title,
          company: game.company || '',
          price: game.price || 0,
          genres: game.genres || [],
          background: game.background || '',
          gameplay: game.gameplay || '',
          officialUrl: game.official_url || '',
          cover: game.cover_url || '',
          gallery: gallery, // 从 game_images 表加载的图集
          createdAt: new Date(game.created_at).getTime(),
          creator: game.profiles?.name || '匿名',
          supabase_id: game.id
        };
      });
      
      // 合并到现有游戏数据中，避免重复
      const existingIds = new Set(store.games.map(g => g.supabase_id).filter(Boolean));
      const newGames = convertedGames.filter(g => !existingIds.has(g.id));
      store.games = [...newGames, ...store.games];
      
      console.log(`已加载 ${newGames.length} 个游戏，包含图集数据`);

      // 批量加载评分聚合（avg/count），避免拉回所有评分行
      try {
        const gameIds = newGames.map(g => g.id);
        if (gameIds.length > 0) {
          const { data: aggs, error: aggErr } = await supabase
            .from('ratings')
            .select('game_id, avg:stars.avg(), count:stars.count()')
            .in('game_id', gameIds)
            .group('game_id');
          if (aggErr) {
            console.warn('批量加载评分聚合失败:', aggErr);
          } else {
            const map = {};
            (aggs || []).forEach(r => {
              map[r.game_id] = {
                avg: Math.round((Number(r.avg) || 0) * 10) / 10,
                count: Number(r.count) || 0
              };
            });
            store.games = store.games.map(g => {
              if (g.supabase_id && map[g.supabase_id]) {
                const m = map[g.supabase_id];
                return { ...g, avg: m.avg, count: m.count };
              }
              return g;
            });
          }
        }
      } catch (e) {
        console.warn('批量加载评分聚合异常:', e);
      }
    }
    
    // 加载帖子数据（包含图片）
    const { data: postsData, error: postsError } = await supabase
      .from('posts')
      .select(`
        *,
        profiles:author_id(name, avatar_url),
        post_images(image_url, position),
        post_comments(
          *,
          profiles:author_id(name, avatar_url)
        )
      `)
      .order('created_at', { ascending: false });
    
    if (postsError) {
      console.error('加载帖子数据失败:', postsError);
    } else if (postsData && postsData.length > 0) {
      // 转换 Supabase 数据格式为本地格式
      const convertedPosts = postsData.map(post => {
        // 处理帖子图片数据
        const images = post.post_images 
          ? post.post_images
              .sort((a, b) => a.position - b.position) // 按位置排序
              .map(img => img.image_url)
          : [];
        
        return {
          id: post.id,
          title: post.title,
          author: post.author_name || post.profiles?.name || '匿名',
          author_id: post.author_id || null,
          content: post.content || '',
          createdAt: new Date(post.created_at).getTime(),
          likes: post.likes || 0,
          images: images, // 从 post_images 表加载的图片
          comments: (post.comments || []).map(comment => ({
            id: comment.id,
            author: comment.author_name || comment.profiles?.name || '匿名',
            content: comment.content,
            createdAt: new Date(comment.created_at).getTime()
          })),
          supabase_id: post.id
        };
      });
      
      // 合并到现有帖子数据中，避免重复
      const existingPostIds = new Set(store.posts.map(p => p.supabase_id).filter(Boolean));
      const newPosts = convertedPosts.filter(p => !existingPostIds.has(p.id));
      store.posts = [...newPosts, ...store.posts];
      
      console.log(`已加载 ${newPosts.length} 个帖子，包含图片数据`);
    }
    
    console.log('数据加载完成');
    return true;
  } catch (error) {
    console.error('从 Supabase 加载数据时出错:', error);
    return false;
  }
}

// 上传图片到 Supabase Storage
async function uploadImageToStorage(imageDataUrl, fileName, bucket = 'game-gallery') {
  try {
    // 将 base64 转换为 Blob
    const response = await fetch(imageDataUrl);
    const blob = await response.blob();
    
    // 生成简单安全的文件名
    const timestamp = Date.now();
    const randomId = Math.random().toString(36).substring(2, 15);
    const fileExtension = blob.type.split('/')[1] || 'jpg';
    // 使用简单的文件名格式，避免复杂路径
    const uniqueFileName = `${timestamp}-${randomId}.${fileExtension}`;
    
    console.log('尝试上传文件:', uniqueFileName);
    
    // 上传到 Supabase Storage
    const { data, error } = await supabase.storage
      .from(bucket)
      .upload(uniqueFileName, blob, {
        contentType: blob.type,
        upsert: false
      });
    
    if (error) {
      console.error('上传图片失败:', error);
      console.error('错误详情:', error.message);
      
      // 如果是 RLS 策略问题，尝试使用用户 ID 作为文件夹
      if (error.message.includes('row-level security policy')) {
        const userId = store.user?.id;
        if (userId) {
          const userFileName = `${userId}/${uniqueFileName}`;
          console.log('尝试使用用户文件夹:', userFileName);
          
          const { data: userData, error: userError } = await supabase.storage
            .from(bucket)
            .upload(userFileName, blob, {
              contentType: blob.type,
              upsert: false
            });
          
          if (userError) {
            console.error('用户文件夹上传也失败:', userError);
            return null;
          }
          
          // 获取公开 URL
          const { data: urlData } = supabase.storage
            .from(bucket)
            .getPublicUrl(userFileName);
          
          return urlData.publicUrl;
        }
      }
      
      return null;
    }
    
    // 获取公开 URL
    const { data: urlData } = supabase.storage
      .from(bucket)
      .getPublicUrl(uniqueFileName);
    
    return urlData.publicUrl;
  } catch (error) {
    console.error('上传图片过程中出错:', error);
    return null;
  }
}

export async function addGame(game) {
  const id = newId('g');
  const title = game.title?.trim() || '未命名游戏';
  const company = game.company?.trim() || '未知公司';
  const price = Number(game.price) || 0;
  const genre = (game.genre?.trim() || (Array.isArray(game.genres) && game.genres[0]) || '未分类');
  const genres = parseGenres(game.genres, (game.genre?.trim() || '未分类'));
  const background = game.background?.trim() || '';
  const gameplay = game.gameplay?.trim() || '';
  const officialUrl = game.officialUrl?.trim() || '';
  const cover = game.cover?.trim() || '';
  const gallery = parseGallery(game.gallery);
  const creatorName = store.user?.name || '匿名';
  
  let supabaseGameId = null;
  let coverUrl = cover; // 默认使用原始封面
  let galleryUrls = []; // 存储上传后的图片 URL
  
  // 1. 首先保存到本地（不包含大图片数据，避免 localStorage 配额问题）
  const newGame = {
    id,
    title,
    company,
    price,
    genre,
    genres,
    background,
    gameplay,
    officialUrl,
    cover: '', // 暂时为空，等上传后更新
    gallery: [], // 暂时为空，等上传后更新
    createdAt: Date.now(),
    creator: creatorName,
    supabase_id: null
  };
  // 延后入列表：仅当写库成功后再 push
  
  // 2. 上传图片到 Supabase Storage
  try {
    // 上传封面图片
    if (cover && cover.startsWith('data:')) {
      console.log('正在上传封面图片...');
      // 使用安全的文件名
      const safeTitle = title.replace(/[^a-zA-Z0-9]/g, '_').substring(0, 20);
      coverUrl = await uploadImageToStorage(cover, `cover_${safeTitle}`, 'game-gallery');
      if (coverUrl) {
        newGame.cover = coverUrl; // 更新本地封面 URL
        console.log('封面上传成功:', coverUrl);
      } else {
        console.warn('封面上传失败，使用默认图片');
      }
    }
    
    // 上传图集图片
    if (gallery && gallery.length > 0) {
      console.log(`正在上传 ${gallery.length} 张图集图片...`);
      for (let i = 0; i < gallery.length; i++) {
        const imageDataUrl = gallery[i];
        if (imageDataUrl && imageDataUrl.startsWith('data:')) {
          // 使用安全的文件名
          const safeTitle = title.replace(/[^a-zA-Z0-9]/g, '_').substring(0, 20);
          const uploadedUrl = await uploadImageToStorage(imageDataUrl, `gallery_${safeTitle}_${i}`, 'game-gallery');
          if (uploadedUrl) {
            galleryUrls.push(uploadedUrl);
            console.log(`图集 ${i + 1} 上传成功:`, uploadedUrl);
          } else {
            console.warn(`图集 ${i + 1} 上传失败`);
          }
        }
      }
      // 更新本地图集 URL
      if (galleryUrls.length > 0) {
        newGame.gallery = galleryUrls;
        console.log(`成功上传 ${galleryUrls.length} 张图集图片`);
      }
    }
  } catch (error) {
    console.error('上传图片时出错:', error);
  }
  
  // 3. 保存游戏信息到 Supabase
  try {
    const currentUserId = store.user?.id;
    
    const { data, error } = await supabase
      .from('games')
      .insert([
        {
          title: title,
          company: company,
          price: price,
          genres: genres,
          background: background,
          gameplay: gameplay,
          official_url: officialUrl,
          cover_url: coverUrl, // 使用上传后的封面 URL
          creator: currentUserId,
          created_at: new Date().toISOString()
        }
      ])
      .select();
    
    if (error) {
      console.error('保存游戏到Supabase失败:', error);
      return { localId: id, supabaseId: null };
    }
    
    console.log('游戏已保存到Supabase:', data);
    
    if (data && data.length > 0) {
      supabaseGameId = data[0].id;
      newGame.supabase_id = supabaseGameId;
      
      // 严格以DB成功为准，现在推入本地列表
      store.games.unshift(newGame);
      
      // 4. 保存图集到 game_images 表
      if (galleryUrls.length > 0) {
        console.log(`正在保存 ${galleryUrls.length} 张图片到图集表...`);
        const imageRecords = galleryUrls.map((url, index) => ({
          game_id: supabaseGameId,
          image_url: url,
          position: index,
          created_at: new Date().toISOString()
        }));
        
        const { data: imageData, error: imageError } = await supabase
          .from('game_images')
          .insert(imageRecords)
          .select();
        
        if (imageError) {
          console.error('保存图集到数据库失败:', imageError);
        } else {
          console.log('图集已保存到数据库:', imageData);
        }
      }
      
      // 5. 添加到审核队列
      try {
        const { error: queueError } = await supabase
          .from('moderation_queue')
          .insert([{
            content_type: 'game',
            content_id: supabaseGameId,
            submitter_id: currentUserId,
            created_at: new Date().toISOString()
          }]);
        
        if (queueError) {
          console.error('添加到审核队列失败:', queueError);
        } else {
          console.log('游戏已添加到审核队列');
        }
      } catch (error) {
        console.error('添加到审核队列时出错:', error);
      }
    }
    
  } catch (error) {
    console.error('保存游戏过程中出错:', error);
  }
  
  return { localId: id, supabaseId: supabaseGameId };
}

// getGame函数已移至文件末尾，确保数据结构完整

// 原addRating函数已被重写，新版本在文件末尾

export function getAverageStars(g) {
  const list = Array.isArray(g?.ratings) ? g.ratings : [];
  if (list.length === 0) return 0;
  const sum = list.reduce((acc, x) => acc + (Number(x.rating ?? x.stars) || 0), 0);
  return Math.round((sum / list.length) * 10) / 10;
}

export async function addPost(post) {
  const id = newId('p');
  const authorName = post.author?.trim() || store.user?.name || '匿名';
  const title = post.title?.trim() || '无标题';
  const content = post.content?.trim() || '';
  const images = Array.isArray(post.images) ? post.images : [];
  
  let supabasePostId = null;
  let uploadedImageUrls = []; // 存储上传后的图片 URL
  
  // 1. 首先保存到本地（不包含大图片数据）
  const newPost = {
    id,
    title,
    author: authorName, // 显示用昵称快照
    author_id: store.user?.id || null, // 所有权依据
    content,
    createdAt: Date.now(),
    likes: 0,
    images: [], // 暂时为空，等上传后更新
    comments: [],
    supabase_id: null
  };
  // 延后入列表：仅当写库成功后再 push
  
  // 2. 上传图片到 Supabase Storage
  if (images.length > 0) {
    console.log(`正在上传 ${images.length} 张帖子图片...`);
    for (let i = 0; i < images.length; i++) {
      const imageDataUrl = images[i];
      if (imageDataUrl && imageDataUrl.startsWith('data:')) {
        // 使用安全的文件名
        const safeTitle = title.replace(/[^a-zA-Z0-9]/g, '_').substring(0, 20);
        const uploadedUrl = await uploadImageToStorage(imageDataUrl, `post_${safeTitle}_${i}`, 'post-images');
        if (uploadedUrl) {
          uploadedImageUrls.push(uploadedUrl);
          console.log(`帖子图片 ${i + 1} 上传成功:`, uploadedUrl);
        } else {
          console.warn(`帖子图片 ${i + 1} 上传失败`);
        }
      }
    }
    // 更新本地帖子的图片 URL
    if (uploadedImageUrls.length > 0) {
      newPost.images = uploadedImageUrls;
      console.log(`成功上传 ${uploadedImageUrls.length} 张帖子图片`);
    }
  }
  
  // 3. 保存帖子信息到 Supabase
  try {
    const currentUserId = store.user?.id;
    
    const { data, error } = await supabase
      .from('posts')
      .insert([
        {
          title: title,
          author_id: currentUserId,
          author_name: authorName,
          content: content,
          likes: 0,
          created_at: new Date().toISOString()
        }
      ])
      .select();
    
    if (error) {
      console.error('保存帖子到Supabase失败:', error);
      return { localId: id, supabaseId: null };
    }
    
    console.log('帖子已保存到Supabase:', data);
    
    if (data && data.length > 0) {
      supabasePostId = data[0].id;
      newPost.supabase_id = supabasePostId;
      
      // 严格以DB成功为准，现在推入本地列表
      store.posts.unshift(newPost);
      
      // 4. 保存图片到 post_images 表
      if (uploadedImageUrls.length > 0) {
        console.log(`正在保存 ${uploadedImageUrls.length} 张图片到帖子图片表...`);
        const imageRecords = uploadedImageUrls.map((url, index) => ({
          post_id: supabasePostId,
          image_url: url,
          position: index,
          created_at: new Date().toISOString()
        }));
        
        const { data: imageData, error: imageError } = await supabase
          .from('post_images')
          .insert(imageRecords)
          .select();
        
        if (imageError) {
          console.error('保存帖子图片到数据库失败:', imageError);
        } else {
          console.log('帖子图片已保存到数据库:', imageData);
        }
      }
      
      // 5. 添加到审核队列
      try {
        const { error: queueError } = await supabase
          .from('moderation_queue')
          .insert([{
            content_type: 'post',
            content_id: supabasePostId,
            submitter_id: currentUserId,
            created_at: new Date().toISOString()
          }]);
        
        if (queueError) {
          console.error('添加到审核队列失败:', queueError);
        } else {
          console.log('帖子已添加到审核队列');
        }
      } catch (error) {
        console.error('添加到审核队列时出错:', error);
      }
    }
    
  } catch (error) {
    console.error('保存帖子过程中出错:', error);
  }
  
  // 确保本地数据已更新
  console.log('最终本地帖子数据:', newPost);
  
  return { localId: id, supabaseId: supabasePostId };
}

export function getPost(id) {
  return store.posts.find(p => p.id === id);
}

// 为现有帖子创建Supabase记录（如果不存在）
async function ensurePostHasSupabaseId(post) {
  if (post.supabase_id) {
    return post.supabase_id;
  }
  
  try {
    // 获取当前登录用户的ID
    const currentUserId = store.user?.id;
    
    const { data, error } = await supabase
      .from('posts')
      .insert([
        {
          title: post.title,
          author_id: currentUserId,
          author_name: post.author,
          content: post.content,
          likes: post.likes || 0,
          created_at: new Date(post.createdAt).toISOString()
        }
      ])
      .select();
    
    if (error) {
      console.error('为现有帖子创建Supabase记录失败:', error);
      return null;
    }
    
    if (data && data.length > 0) {
      const supabaseId = data[0].id;
      post.supabase_id = supabaseId;
      console.log('已为现有帖子创建Supabase记录:', supabaseId);
      return supabaseId;
    }
  } catch (error) {
    console.error('为现有帖子创建Supabase记录过程中出错:', error);
  }
  
  return null;
}

export async function addComment(postId, comment) {
  const p = getPost(postId);
  if (!p) return null;
  if (!store.user?.id) return null; // 未登录不允许操作
  const id = newId('c');
  const authorName = comment.author?.trim() || store.user?.name || '匿名';
  const content = comment.content?.trim() || '';
  
  // 仅在写库成功后再入本地
  const newComment = {
    id,
    db_id: null,
    author: authorName,
    author_id: store.user?.id || null,
    content,
    createdAt: Date.now()
  };
  
  // 2. 然后尝试保存到 Supabase
  try {
    // 获取当前登录用户的ID
    const currentUserId = store.user?.id;
    
    // 使用帖子的Supabase ID（如果存在）
    let supabasePostId = p.supabase_id;
    
    // 如果没有Supabase ID，尝试为现有帖子创建Supabase记录
    if (!supabasePostId) {
      supabasePostId = await ensurePostHasSupabaseId(p);
      if (!supabasePostId) {
        console.warn('无法为帖子创建Supabase记录，跳过数据库保存');
        return id;
      }
    }
    
    // 检查用户是否已登录（需要author_id）
    if (!currentUserId) {
      console.warn('用户未登录，跳过数据库保存');
      return id;
    }
    
    const { data, error } = await supabase
      .from('post_comments')
      .insert([
        {
          post_id: supabasePostId,
          author_id: currentUserId,
          author_name: authorName,
          content: content,
          created_at: new Date().toISOString()
        }
      ])
      .select();
    
    if (error) {
      console.error('保存评论到Supabase失败:', error);
      return null;
    }
    
    console.log('评论已保存到Supabase:', data);
    if (Array.isArray(data) && data.length > 0) newComment.db_id = data[0].id;
    
    if (!Array.isArray(p.comments)) p.comments = [];
    p.comments.push(newComment);
    
  } catch (error) {
    console.error('保存评论过程中出错:', error);
    return null;
  }
  
  return id;
}

export async function deletePostComment(postId, commentId) {
  if (!store.user?.id) return false;
  const p = getPost(postId);
  if (!p || !Array.isArray(p.comments)) return false;
  const idx = p.comments.findIndex(c => c.id === commentId);
  if (idx === -1) return false;
  const c = p.comments[idx];
  const canModerate = !!store.user?.is_moderator;
  const isOwner = (c.author_id && store.user?.id && c.author_id === store.user.id) || (!c.author_id && c.author && store.user?.name && c.author === store.user.name);
  if (!(canModerate || isOwner)) return false;
  try {
    const targetId = c.db_id || c.id;
    if (targetId) {
      const { error } = await supabase.from('post_comments').delete().eq('id', targetId);
      if (error) { console.error('删除帖子评论失败:', error); return false; }
    }
    p.comments.splice(idx, 1);
    return true;
  } catch (e) {
    console.error('删除帖子评论异常:', e);
    return false;
  }
}

export async function likePost(postId) {
  if (!store.user?.id) return { ok: false, reason: 'auth' }; // 必须登录
  const p = getPost(postId);
  if (!p) return { ok: false, reason: 'not_found' };

  // 必须有 Supabase 记录，才能进行一次性点赞约束
  if (!p.supabase_id) {
    console.warn('该帖子尚未同步到数据库，无法点赞');
    return { ok: false, reason: 'no_supabase' };
  }

  try {
    const payload = { post_id: p.supabase_id, user_id: store.user.id };
    const { error } = await supabase.from('post_likes').insert([payload]);

    if (error) {
      // 23505: unique_violation（重复点赞）
      if (error.code === '23505' || /unique/i.test(error.message || '')) {
        console.info('用户已点赞过该帖子');
        p.likedByMe = true; // 同步本地状态
        return { ok: false, reason: 'already' };
      }
      console.error('点赞失败:', error);
      return { ok: false, reason: 'db_error', error };
    }

    // 成功插入关系，本地计数 +1，并标记 likedByMe
    p.likes = (p.likes || 0) + 1;
    p.likedByMe = true;
    return { ok: true, count: p.likes };
  } catch (e) {
    console.error('点赞异常:', e);
    return { ok: false, reason: 'exception', error: e };
  }
}

export async function unlikePost(postId) {
  if (!store.user?.id) return { ok: false, reason: 'auth' };
  const p = getPost(postId);
  if (!p) return { ok: false, reason: 'not_found' };
  if (!p.supabase_id) return { ok: false, reason: 'no_supabase' };
  try {
    const { error } = await supabase
      .from('post_likes')
      .delete()
      .eq('post_id', p.supabase_id)
      .eq('user_id', store.user.id);
    if (error) {
      console.error('取消点赞失败:', error);
      return { ok: false, reason: 'db_error', error };
    }
    // 触发器会自减，这里同步本地
    p.likes = Math.max((p.likes || 0) - 1, 0);
    p.likedByMe = false;
    return { ok: true, count: p.likes };
  } catch (e) {
    console.error('取消点赞异常:', e);
    return { ok: false, reason: 'exception', error: e };
  }
}

export async function loadPostLikedState(postId) {
  const p = getPost(postId);
  if (!p || !p.supabase_id || !store.user?.id) return false;
  try {
    const { data, error } = await supabase
      .from('post_likes')
      .select('id')
      .eq('post_id', p.supabase_id)
      .eq('user_id', store.user.id)
      .limit(1);
    if (error) { console.warn('查询点赞状态失败（可忽略）:', error); return false; }
    p.likedByMe = Array.isArray(data) && data.length > 0;
    return p.likedByMe;
  } catch (e) {
    console.warn('查询点赞状态异常（可忽略）:', e);
    return false;
  }
}

// 删除帖子（作者可删自己的；审核员可删所有）
export async function deletePost(postId) {
  if (!store.user?.id) { console.error('未登录用户无法删除帖子'); return false; }

  const postIndex = store.posts.findIndex(p => p.id === postId);
  if (postIndex === -1) { console.error('帖子不存在'); return false; }
  const post = store.posts[postIndex];

  const isOwner = (post.author_id && store.user?.id && post.author_id === store.user.id) || (post.author && store.user?.name && post.author === store.user.name);
  const canModerate = !!store.user?.is_moderator;
  if (!(isOwner || canModerate)) { console.error('无权限删除此帖子'); return false; }

  // 提取 Supabase Storage 对象路径（仅限 post-images 桶）
  const extractStoragePath = (url) => {
    if (!url || typeof url !== 'string') return null;
    try {
      const u = new URL(url);
      const p = u.pathname; // /storage/v1/object/public/post-images/<key>
      const patterns = [
        '/object/public/post-images/',
        '/object/post-images/',
        '/storage/v1/object/public/post-images/',
        '/storage/v1/object/post-images/'
      ];
      for (const marker of patterns) {
        const idx = p.indexOf(marker);
        if (idx !== -1) return p.substring(idx + marker.length);
      }
      const raw = url;
      for (const marker of patterns) {
        const idx = raw.indexOf(marker);
        if (idx !== -1) return raw.substring(idx + marker.length).split('?')[0];
      }
      return null;
    } catch { return null; }
  };

  try {
    // 1) 删除 Storage 图片（先收集）
    const paths = [];
    if (Array.isArray(post.images)) {
      for (const img of post.images) { const p = extractStoragePath(img); if (p) paths.push(p); }
    }
    if (post.supabase_id) {
      try {
        const { data: imgs } = await supabase.from('post_images').select('image_url').eq('post_id', post.supabase_id);
        (imgs || []).forEach(r => { const p = extractStoragePath(r.image_url); if (p) paths.push(p); });
      } catch (e) { console.warn('补充查询帖子图片失败（可忽略）:', e); }
    }
    const uniq = Array.from(new Set(paths));
    if (uniq.length > 0) {
      try {
        const { data: removed, error: removeErr } = await supabase.storage.from('post-images').remove(uniq);
        if (removeErr) console.warn('删除帖子图片失败（可忽略）:', removeErr); else console.log('已从 Storage 删除帖子图片:', removed);
      } catch (e) { console.warn('调用 Storage 删除帖子图片异常（可忽略）:', e); }
    }

    // 2) 删除数据库记录（评论、图片、帖子本身）
    if (post.supabase_id) {
      try { await supabase.from('post_comments').delete().eq('post_id', post.supabase_id); } catch (e) { console.warn('删除关联 post_comments 失败:', e); }
      try { await supabase.from('post_images').delete().eq('post_id', post.supabase_id); } catch (e) { console.warn('删除关联 post_images 失败:', e); }

      const { error } = await supabase.from('posts').delete().eq('id', post.supabase_id);
      if (error) { console.error('从数据库删除帖子失败:', error); return false; }
    }

    // 3) 本地删除（仅当数据库删除成功或不存在 supabase_id）
    store.posts.splice(postIndex, 1);
    console.log('已删除帖子:', postId);
    return true;
  } catch (error) {
    console.error('删除帖子过程中出错:', error);
    return false;
  }
}

// 删除游戏（仅审核员）
export async function deleteGame(gameId) {
  // 仅审核员
  if (!store.user?.is_moderator) {
    console.error('只有审核员可以删除游戏');
    return false;
  }

  const gameIndex = store.games.findIndex(g => g.id === gameId);
  if (gameIndex === -1) {
    console.error('游戏不存在');
    return false;
  }
  const game = store.games[gameIndex];

  // 提取 Supabase Storage 对象路径（仅限 game-gallery 桶）
  const extractStoragePath = (url) => {
    if (!url || typeof url !== 'string') return null;
    try {
      const u = new URL(url);
      const p = u.pathname; // /storage/v1/object/public/game-gallery/<key>
      const patterns = [
        '/object/public/game-gallery/',
        '/object/game-gallery/',
        '/storage/v1/object/public/game-gallery/',
        '/storage/v1/object/game-gallery/'
      ];
      for (const marker of patterns) {
        const idx = p.indexOf(marker);
        if (idx !== -1) return p.substring(idx + marker.length);
      }
      const raw = url;
      for (const marker of patterns) {
        const idx = raw.indexOf(marker);
        if (idx !== -1) return raw.substring(idx + marker.length).split('?')[0];
      }
      return null;
    } catch {
      return null;
    }
  };

  try {
    // 1) 删除 Storage 图片（封面 + 图集）
    const paths = [];
    const coverPath = extractStoragePath(game.cover);
    if (coverPath) paths.push(coverPath);
    if (Array.isArray(game.gallery)) {
      for (const img of game.gallery) {
        const p = extractStoragePath(img);
        if (p) paths.push(p);
      }
    }
    // 补充：从数据库再查一次图集，避免本地缓存不全
    if (game.supabase_id) {
      try {
        const { data: imgs } = await supabase.from('game_images').select('image_url').eq('game_id', game.supabase_id);
        (imgs || []).forEach(r => { const p = extractStoragePath(r.image_url); if (p) paths.push(p); });
      } catch (e) { console.warn('补充查询图集失败（可忽略）:', e); }
    }
    // 去重
    const uniq = Array.from(new Set(paths));
    if (uniq.length > 0) {
      try {
        const { data: removed, error: removeErr } = await supabase.storage.from('game-gallery').remove(uniq);
        if (removeErr) {
          console.warn('删除 Storage 图片失败（可忽略）:', removeErr);
        } else {
          console.log('已从 Storage 删除对象:', removed);
        }
      } catch (e) {
        console.warn('调用 Storage 删除接口异常（可忽略）:', e);
      }
    }

    // 2) 删除数据库记录
    if (game.supabase_id) {
      try {
        await supabase.from('game_images').delete().eq('game_id', game.supabase_id);
      } catch (e) {
        console.warn('删除关联图片记录失败（可忽略）:', e);
      }
      // 先清理关联数据（容错）
      try { await supabase.from('game_comments').delete().eq('game_id', game.supabase_id); } catch (e) { console.warn('删除关联 game_comments 失败:', e); }
      try { await supabase.from('ratings').delete().eq('game_id', game.supabase_id); } catch (e) { console.warn('删除关联 ratings 失败:', e); }

      const { error } = await supabase
        .from('games')
        .delete()
        .eq('id', game.supabase_id);
      if (error) {
        console.error('从数据库删除游戏失败:', error);
        // 数据库未删除成功，直接返回失败，不移除本地项
        return false;
      }
    }

    // 3) 本地删除（只有在数据库删除成功或不存在 supabase_id 才执行）
    store.games.splice(gameIndex, 1);
    console.log('审核员已删除游戏:', gameId);
    return true;
  } catch (error) {
    console.error('删除游戏过程中出错:', error);
    return false;
  }
}

// 普通用户删除自己发布的游戏
export async function deleteMyGame(gameId) {
  if (!store.user) {
    console.error('未登录用户无法删除');
    return false;
  }
  const idx = store.games.findIndex(g => g.id === gameId);
  if (idx === -1) {
    console.error('游戏不存在');
    return false;
  }
  const game = store.games[idx];
  // 个人中心里，creator 为用户名字符串
  if (game.creator !== store.user.name) {
    console.error('只能删除自己发布的游戏');
    return false;
  }

  // 提取 Supabase Storage 对象路径（仅限 game-gallery 桶）
  const extractStoragePath = (url) => {
    if (!url || typeof url !== 'string') return null;
    try {
      const u = new URL(url);
      const p = u.pathname;
      const patterns = [
        '/object/public/game-gallery/',
        '/object/game-gallery/',
        '/storage/v1/object/public/game-gallery/',
        '/storage/v1/object/game-gallery/'
      ];
      for (const marker of patterns) {
        const idx = p.indexOf(marker);
        if (idx !== -1) return p.substring(idx + marker.length);
      }
      const raw = url;
      for (const marker of patterns) {
        const idx = raw.indexOf(marker);
        if (idx !== -1) return raw.substring(idx + marker.length).split('?')[0];
      }
      return null;
    } catch { return null; }
  };

  try {
    // 1) 删除 Storage 图片（封面 + 图集）
    const paths = [];
    const coverPath = extractStoragePath(game.cover);
    if (coverPath) paths.push(coverPath);
    if (Array.isArray(game.gallery)) {
      for (const img of game.gallery) {
        const p = extractStoragePath(img);
        if (p) paths.push(p);
      }
    }
    // 补充：从数据库再查一次图集，避免本地缓存不全
    if (game.supabase_id) {
      try {
        const { data: imgs } = await supabase.from('game_images').select('image_url').eq('game_id', game.supabase_id);
        (imgs || []).forEach(r => { const p = extractStoragePath(r.image_url); if (p) paths.push(p); });
      } catch (e) { console.warn('补充查询图集失败（可忽略）:', e); }
    }
    // 去重
    const uniq = Array.from(new Set(paths));
    if (uniq.length > 0) {
      try {
        const { data: removed, error: removeErr } = await supabase.storage.from('game-gallery').remove(uniq);
        if (removeErr) {
          console.warn('删除 Storage 图片失败（可忽略）:', removeErr);
        } else {
          console.log('已从 Storage 删除对象:', removed);
        }
      } catch (e) {
        console.warn('调用 Storage 删除接口异常（可忽略）:', e);
      }
    }

    // 2) 删除数据库记录
    if (game.supabase_id) {
      // 先尝试删除关联的 game_images 记录（若无外键级联）
      try {
        await supabase.from('game_images').delete().eq('game_id', game.supabase_id);
      } catch (e) {
        console.warn('删除关联图片记录失败（可忽略）:', e);
      }
      const { error } = await supabase
        .from('games')
        .delete()
        .eq('id', game.supabase_id);
      if (error) {
        console.error('从数据库删除游戏失败:', error);
        // 即使失败也继续本地删除，保证前端一致性
      }
    }

    // 3) 本地删除
    store.games.splice(idx, 1);
    console.log('已删除自己发布的游戏:', gameId);
    return true;
  } catch (err) {
    console.error('删除自己发布的游戏出错:', err);
    return false;
  }
}

/* 用户状态（本地持久化） */
export function getUser() {
  return store.user || null;
}

// 检查用户名或邮箱是否已存在
async function isUserExists(username, email) {
  try {
    // 检查用户名是否已存在
    if (username) {
      const { data: usernameData, error: usernameError } = await supabase
        .from('profiles')
        .select('id')
        .eq('name', username)
        .single();
      
      if (usernameData && !usernameError) {
        return true;
      }
    }
    
    // 检查邮箱是否已存在
    if (email) {
      const { data: emailData, error: emailError } = await supabase
        .from('profiles')
        .select('id')
        .eq('email', email)
        .single();
      
      if (emailData && !emailError) {
        return true;
      }
    }
    
    return false;
  } catch (error) {
    console.error('检查用户存在性时出错:', error);
    return false;
  }
}

export async function signUp(payload) {
  const username = (payload?.username || '').trim();
  const email = (payload?.email || '').trim();
  const password = (payload?.password || '').trim();
  
  // 基本校验
  if (!username || username.length < 3) {
    return false;
  }
  if (!email || !email.includes('@')) {
    return false;
  }
  if (!password || password.length < 6) {
    return false;
  }
  
  try {
    // 检查用户名或邮箱是否已存在
    const exists = await isUserExists(username, email);
    if (exists) {
      return false;
    }
    
    // 1. 首先在Supabase Auth中创建用户
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email: email,
      password: password,
      options: {
        data: {
          username: username
        }
      }
    });
    
    if (authError) {
      console.error('Supabase Auth注册失败:', authError);
      return false;
    }
    
    if (!authData.user) {
      return false;
    }
    
    // 2. 在profiles表中创建用户档案
    const { data: profileData, error: profileError } = await supabase
      .from('profiles')
      .insert([
        {
          id: authData.user.id,
          name: username,
          avatar_url: null
          // created_at 字段有默认值，不需要手动设置
        }
      ])
      .select();
    
    if (profileError) {
      console.error('创建用户档案失败:', profileError);
      // 如果档案创建失败，可能需要回滚Auth用户创建
      return false;
    }
    
    // 3. 设置当前登录用户
    store.user = {
      id: authData.user.id,
      name: username,
      username: username,
      email: email,
      is_moderator: false, // 新用户默认不是审核员
      createdAt: new Date().toISOString()
    };
    
    // 4. 同时保存到本地profiles
    store.profiles[username] = store.user;
    
    return true;
  } catch (error) {
    console.error('注册过程中出错:', error);
    return false;
  }
}

export async function signIn(payload, opts = {}) {
  const email = (payload?.email || '').trim();
  const password = (payload?.password || '').trim();
  
  try {
    // 简单校验：邮箱需含 @；密码非空
    if (!email.includes('@') || !password) return false;
    
    // 使用Supabase Auth进行邮箱登录
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
      email: email,
      password: password
    });
    
    if (authError) {
      console.error('Supabase Auth登录失败:', authError);
      return false;
    }
    
    if (!authData.user) {
      return false;
    }
    
    // 获取用户档案信息
    const { data: profileData, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', authData.user.id)
      .single();
    
    if (profileError) {
      console.error('获取用户档案失败:', profileError);
      return false;
    }
    
    // 设置当前登录用户
    store.user = {
      id: authData.user.id,
      name: profileData.name,
      email: authData.user.email,
      username: profileData.name,
      avatar_url: profileData.avatar_url,
      is_moderator: profileData.is_moderator || false,
      createdAt: profileData.created_at
    };
    
    // 保存到本地profiles
    store.profiles[profileData.name] = store.user;
    
    return true;
  } catch (error) {
    console.error('登录过程中出错:', error);
    return false;
  }
}
export function signOut() {
  store.user = null;
}


// 发送密码重置邮件
export async function sendPasswordResetEmail(email) {
  try {
    if (!email || !email.includes('@')) {
      throw new Error('请输入有效的邮箱地址');
    }

    // 确保使用正确的重定向 URL
    const redirectUrl = window.location.hostname === 'localhost' 
      ? 'http://localhost:5173/reset-password'
      : 'https://gameweb-po34.vercel.app/reset-password';
    
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: redirectUrl
    });

    if (error) {
      console.error('发送密码重置邮件失败:', error);
      throw new Error(error.message || '发送重置邮件失败');
    }

    return { success: true };
  } catch (error) {
    console.error('发送密码重置邮件时出错:', error);
    throw error;
  }
}

// 重置密码
export async function resetPassword(newPassword) {
  try {
    if (!newPassword || newPassword.length < 6) {
      throw new Error('密码至少需要6位');
    }

    const { error } = await supabase.auth.updateUser({
      password: newPassword
    });

    if (error) {
      console.error('重置密码失败:', error);
      throw new Error(error.message || '重置密码失败');
    }

    return { success: true };
  } catch (error) {
    console.error('重置密码时出错:', error);
    throw error;
  }
}

/* 头像与社交关系 */
export function updateAvatar(dataUrl) {
  if (!store.user) return false;
  store.user.avatar = dataUrl;
  const name = store.user.name;
  if (!store.profiles[name]) store.profiles[name] = {};
  store.profiles[name].avatar = dataUrl;
  return true;
}
export function getAvatarByName(name) {
  return store.profiles?.[name]?.avatar || null;
}
function ensureRel(name) {
  if (!store.relations[name]) store.relations[name] = { followers: [], following: [] };
  return store.relations[name];
}
export function isFollowing(targetName) {
  const me = store.user?.name;
  if (!me || !targetName) return false;
  return (ensureRel(me).following).includes(targetName);
}
export function followUser(targetName) {
  const me = store.user?.name;
  if (!me || !targetName || me === targetName) return false;
  const my = ensureRel(me); const his = ensureRel(targetName);
  if (!my.following.includes(targetName)) my.following.push(targetName);
  if (!his.followers.includes(me)) his.followers.push(me);
  return true;
}
export function unfollowUser(targetName) {
  const me = store.user?.name;
  if (!me || !targetName) return false;
  const my = ensureRel(me); const his = ensureRel(targetName);
  my.following = my.following.filter(n => n !== targetName);
  his.followers = his.followers.filter(n => n !== me);
  // 触发响应式
  store.relations = { ...store.relations, [me]: my, [targetName]: his };
  return true;
}
export function followersOf(name) {
  return ensureRel(name).followers.map(n => ({ id: n, name: n, avatar: getAvatarByName(n) }));
}
export function followingOf(name) {
  return ensureRel(name).following.map(n => ({ id: n, name: n, avatar: getAvatarByName(n) }));
}

/* 游戏评分系统 - 每人只能评分一次 */
export function getUserRating(gameId) {
  if (!gameId || !store.user?.name) return 0;
  
  const game = getGame(gameId);
  if (!game || !Array.isArray(game.ratings)) return 0;
  
  const userRating = game.ratings.find(r => r.userId === store.user.name);
  return userRating ? userRating.rating : 0;
}

export async function withdrawUserRating(gameId) {
  if (!gameId || !store.user?.id) return false; // 必须登录
  const game = getGame(gameId);
  if (!game) return false;
  if (!Array.isArray(game.ratings)) game.ratings = [];

  // 先尝试从数据库删除
  try {
    if (game.supabase_id && store.user?.id) {
      const { error } = await supabase
        .from('ratings')
        .delete()
        .eq('game_id', game.supabase_id)
        .eq('user_id', store.user.id);
      if (error) console.warn('撤回评分时数据库删除失败（忽略本地继续）:', error);
    }
  } catch (e) {
    console.warn('撤回评分数据库操作异常（忽略本地继续）:', e);
  }

  const initialLength = game.ratings.length;
  game.ratings = game.ratings.filter(r => r.userId !== store.user.name);
  console.log(`用户 ${store.user.name} 撤回了对游戏 ${game.title} 的评分`);
  return game.ratings.length < initialLength;
}

// 重写原有的addRating函数，支持每人一次评分
export async function addRating(gameId, rating) {
  if (!gameId || !store.user?.name) return false;
  const game = getGame(gameId);
  if (!game) return false;
  if (!Array.isArray(game.ratings)) game.ratings = [];

  // 本地去重/更新
  const idx = game.ratings.findIndex(r => r.userId === store.user.name);
  const ratingData = { userId: store.user.name, rating, createdAt: Date.now() };
  if (idx !== -1) {
    game.ratings[idx] = ratingData;
    console.log(`用户 ${store.user.name} 更新了对游戏 ${game.title} 的评分: ${rating} 星`);
  } else {
    game.ratings.push(ratingData);
    console.log(`用户 ${store.user.name} 对游戏 ${game.title} 评分: ${rating} 星`);
  }

  // 持久化到 Supabase（若有 supabase_id 且已登录）
  try {
    if (game.supabase_id && store.user?.id) {
      // 查询是否已有该用户评分
      const { data: exists, error: qErr } = await supabase
        .from('ratings')
        .select('id')
        .eq('game_id', game.supabase_id)
        .eq('user_id', store.user.id)
        .limit(1)
        .maybeSingle();
      if (qErr && qErr.code !== 'PGRST116') {
        console.warn('查询评分记录失败（已忽略）:', qErr);
      }
      if (exists?.id) {
        const { error: uErr } = await supabase
          .from('ratings')
          .update({ stars: rating, created_at: new Date().toISOString() })
          .eq('id', exists.id);
        if (uErr) console.warn('更新评分失败（已忽略）:', uErr);
      } else {
        const payload = {
          game_id: game.supabase_id,
          user_id: store.user.id,
          stars: rating,
          created_at: new Date().toISOString()
        };
        const { error: iErr } = await supabase.from('ratings').insert([payload]);
        if (iErr) console.warn('插入评分失败（已忽略）:', iErr);
      }
    }
  } catch (e) {
    console.warn('评分持久化异常（已忽略）:', e);
  }

  return true;
}

// 从 Supabase 加载某游戏的评分
export async function loadGameRatings(gameId) {
  const game = getGame(gameId);
  if (!game || !game.supabase_id) return false;
  try {
    const { data, error } = await supabase
      .from('ratings')
      .select('user_id, stars, created_at, profiles!inner(name)')
      .eq('game_id', game.supabase_id);
    if (error) {
      console.error('加载游戏评分失败:', error);
      return false;
    }
    // 映射到本地结构
    game.ratings = (data || []).map(r => ({
      userId: r.profiles?.name || r.user_id,
      rating: r.stars,
      createdAt: new Date(r.created_at).getTime()
    }));
    return true;
  } catch (e) {
    console.error('加载游戏评分异常:', e);
    return false;
  }
}

// 从 Supabase 加载某游戏的评论
export async function loadGameComments(gameId) {
  const game = getGame(gameId);
  if (!game || !game.supabase_id) return false;
  try {
    const { data, error } = await supabase
      .from('game_comments')
      .select('*')
      .eq('game_id', game.supabase_id)
      .order('created_at', { ascending: true });
    if (error) {
      console.error('加载游戏评论失败:', error);
      return false;
    }
    const list = (data || []).map(c => ({
      id: c.id,
      db_id: c.id,
      author: c.author_name || '匿名',
      author_id: c.author_id || null,
      content: c.content || '',
      rating: c.rating || 0,
      createdAt: new Date(c.created_at).getTime(),
      likes: 0
    }));
    game.comments = list;
    return true;
  } catch (e) {
    console.error('加载游戏评论异常:', e);
    return false;
  }
}

/* 游戏评论系统 */
export async function addGameComment(gameId, commentData) {
  if (!gameId || !commentData.content?.trim()) return false;
  
  const game = getGame(gameId);
  if (!game) return false;
  
  if (!Array.isArray(game.comments)) {
    game.comments = [];
  }
  
  const comment = {
    id: newId('gc'),
    db_id: null,
    author: commentData.author || '匿名',
    author_id: store.user?.id || null,
    content: commentData.content.trim(),
    rating: commentData.rating || 0,
    createdAt: Date.now(),
    likes: 0
  };
  
  game.comments.unshift(comment); // 新评论显示在前面
  console.log(`新增游戏评论:`, comment);

  // 持久化到 Supabase（需登录，且有 supabase_id）
  try {
    if (game.supabase_id && store.user?.id) {
      const payload = {
        game_id: game.supabase_id,
        author_id: store.user.id,
        author_name: comment.author,
        content: comment.content,
        rating: comment.rating || null,
        created_at: new Date().toISOString()
      };
      const { data: ins, error } = await supabase.from('game_comments').insert([payload]).select();
      if (error) {
        console.warn('保存游戏评论到数据库失败（前端已显示）:', error);
      } else if (ins && ins.length > 0) {
        comment.db_id = ins[0].id;
      }
    }
  } catch (e) {
    console.warn('持久化游戏评论异常（已忽略）:', e);
  }

  return comment.id;
}

export async function deleteGameComment(gameId, commentId) {
  if (!store.user?.id) return false;
  const game = getGame(gameId);
  if (!game || !Array.isArray(game.comments)) return false;
  const idx = game.comments.findIndex(c => c.id === commentId);
  if (idx === -1) return false;
  const comment = game.comments[idx];
  const canModerate = !!store.user?.is_moderator;
  const isOwner = comment.author_id && store.user?.id && comment.author_id === store.user.id;
  if (!(canModerate || isOwner)) return false;
  try {
    if (comment.db_id) {
      const { error } = await supabase.from('game_comments').delete().eq('id', comment.db_id);
      if (error) { console.error('删除游戏评论失败:', error); return false; }
    }
    game.comments.splice(idx,1);
    return true;
  } catch (e) { console.error('删除游戏评论异常:', e); return false; }
}

export function likeGameComment(gameId, commentId) {
  if (!store.user?.id) return false; // 未登录不允许点赞
  if (!gameId || !commentId) return false;
  
  const game = getGame(gameId);
  if (!game || !Array.isArray(game.comments)) return false;
  
  const comment = game.comments.find(c => c.id === commentId);
  if (!comment) return false;
  
  comment.likes = (comment.likes || 0) + 1;
  console.log(`评论 ${commentId} 获得点赞，当前点赞数: ${comment.likes}`);
  return true;
}

// 确保游戏数据结构完整
function ensureGameStructure(game) {
  if (!game) return null;
  
  if (!Array.isArray(game.ratings)) {
    game.ratings = [];
  }
  
  if (!Array.isArray(game.comments)) {
    game.comments = [];
  }
  
  return game;
}

// 重写getGame函数，确保数据结构完整
export function getGame(id) {
  const game = store.games.find(g => g.id === id);
  return ensureGameStructure(game);
}