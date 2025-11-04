<template>
  <section class="panel" v-if="game">
    <!-- Steam风格：上方标题 -->
    <div class="game-header">
      <h2>{{ game.title }}</h2>
    </div>

    <!-- Steam风格布局：左侧轮播 + 右侧信息卡 -->
    <div class="steam-layout">
      <!-- 左侧：图片轮播 -->
      <div class="left-side">
        <SteamStyleCarousel :images="galleryImages" />
      </div>

      <!-- 右侧：游戏信息卡 -->
      <div class="right-side">
        <div class="game-info-box">
          <!-- 游戏描述 -->
          <div class="game-description" v-if="game.background || game.gameplay">
            <p v-if="game.background">{{ game.background }}</p>
            <p v-if="game.gameplay">{{ game.gameplay }}</p>
          </div>

          <!-- 游戏详细信息 -->
          <div class="game-details">
            <div class="detail-row">
              <span class="detail-label">最近评测：</span>
              <span class="detail-value">
                <span class="review-badge">{{ getReviewStatus() }}</span>
                <span class="review-count">({{ totalRatings }})</span>
              </span>
            </div>

            <div class="detail-row">
              <span class="detail-label">发行日期：</span>
              <span class="detail-value">{{ formatDate(game.createdAt) }}</span>
            </div>

            <div class="detail-row">
              <span class="detail-label">开发者：</span>
              <span class="detail-value detail-link">{{ game.company || '未知' }}</span>
            </div>

            <div class="detail-row">
              <span class="detail-label">发行商：</span>
              <span class="detail-value detail-link">{{ game.company || '未知' }}</span>
            </div>
          </div>

          <!-- 游戏标签 -->
          <div class="game-tags" v-if="game.genres?.length">
            <span class="label-text">此产品的热门用户自定义标签：</span>
            <div class="tags-list">
              <button class="tag-btn" v-for="tag in game.genres" :key="tag">{{ tag }}</button>
            </div>
          </div>

          <!-- 访问官网按钮 -->
          <div class="purchase-area" v-if="game.officialUrl">
            <a :href="game.officialUrl" target="_blank" class="official-site-btn" rel="noopener noreferrer">
              访问官网
            </a>
          </div>
        </div>
      </div>
    </div>

    <!-- 评分系统 -->
    <div class="rating-section">
      <h3>评分</h3>
      <div class="rating-container">
        <div class="stars-display">
          <div class="stars-row">
            <span class="rating-label">平均：</span>
            <div class="stars-avg">
              <span v-for="n in 5" :key="n" class="star" :class="{ filled: n <= Math.round(averageRating) }">★</span>
            </div>
            <span class="rating-text">{{ averageRating.toFixed(1) }} 星 · 共 {{ totalRatings }} 次评分</span>
          </div>
        </div>
        
        <div class="user-rating">
          <div class="rating-input">
            <span class="rating-label">我的评分：</span>
            <div class="stars-input">
              <button
                v-for="n in 5"
                :key="n"
                class="star-btn"
                :class="{ 
                  active: n <= (hover || userRating),
                  'user-rated': userRating > 0 && n <= userRating
                }"
                @mouseenter="hover = n"
                @mouseleave="hover = 0"
                @click="rate(n)"
                :aria-label="`评分 ${n} 星`"
              >★</button>
            </div>
            <button 
              v-if="userRating > 0" 
              class="btn-withdraw" 
              @click="withdrawRating"
              title="撤回评分"
            >
              撤回
            </button>
          </div>
          <div v-if="userRating > 0" class="user-rating-text">
            您已评分：{{ userRating }} 星
          </div>
        </div>
      </div>
    </div>

    <!-- 评论区 -->
    <div class="comments-section">
      <div class="comments-header">
        <h3>评价和评论</h3>
        <span class="comments-count">{{ comments.length }} 条评论</span>
      </div>
      
      <!-- 发表评论 -->
      <div class="comment-form">
        <div class="form-header">
          <div class="user-avatar">
            <div class="avatar-placeholder">{{ newComment.author.charAt(0) || '匿' }}</div>
          </div>
          <div class="form-content">
            <input 
              v-model="newComment.author" 
              class="author-input" 
              placeholder="输入您的昵称"
              maxlength="20"
            />
          </div>
        </div>
        <textarea 
          v-model="newComment.content" 
          class="comment-textarea" 
          placeholder="写下您的评价..."
          rows="3"
          maxlength="500"
        ></textarea>
        <div class="form-actions">
          <span class="char-count">{{ newComment.content.length }}/500</span>
          <button class="btn-submit" @click="submitComment" :disabled="!canSubmit">
            发表评论
          </button>
        </div>
      </div>

      <!-- 评论列表 -->
      <div class="comments-list">
        <div v-for="comment in comments" :key="comment.id" class="comment-item">
          <div class="comment-header">
            <div class="comment-avatar">
              <div class="avatar-placeholder">{{ comment.author.charAt(0) }}</div>
            </div>
            <div class="comment-info">
              <div class="comment-author">{{ comment.author }}</div>
              <div class="comment-rating" v-if="comment.rating">
                <span v-for="n in 5" :key="n" class="comment-star" :class="{ filled: n <= comment.rating }">★</span>
              </div>
              <div class="comment-time">{{ formatTime(comment.createdAt) }}</div>
              <button v-if="canWithdrawComment(comment)" class="link danger" :disabled="isWithdrawingComment" @click="withdrawComment(comment)">撤回</button>
            </div>
          </div>
          <div class="comment-content">{{ comment.content }}</div>
          <div class="comment-actions">
            <button class="action-btn" @click="likeComment(comment.id)">
              <span class="action-icon">👍</span>
              <span>{{ comment.likes || 0 }}</span>
            </button>
          </div>
        </div>
        
        <div v-if="comments.length === 0" class="empty-comments">
          暂无评论，快来发表第一条评价吧！
        </div>
      </div>
    </div>

    <div class="actions">
      <router-link class="btn secondary" to="/">返回目录</router-link>
      <router-link class="btn" to="/forum">去论坛交流</router-link>
      <button v-if="isOwner || isModerator" class="btn" :disabled="isDeleting" @click="onDelete" aria-busy="isDeleting">
        {{ isDeleting ? '正在删除...' : '删除此游戏' }}
      </button>
    </div>

    <div v-if="isDeleting" class="blocking-modal" role="alertdialog" aria-live="assertive">
      正在删除...
    </div>
  </section>

  <section v-else class="panel">
    <h2>未找到该游戏</h2>
    <router-link class="btn" to="/">返回目录</router-link>
  </section>
</template>

<script setup>
import { ref, computed, reactive, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { store, getGame, addRating, getAverageStars, getUserRating, withdrawUserRating, addGameComment, likeGameComment, deleteMyGame, deleteGame as deleteGameByModerator, loadGameComments, loadGameRatings, deleteGameComment } from '../store';
import SteamStyleCarousel from './SteamStyleCarousel.vue';
import { getGalleryImages } from '../utils/imageUtils.js';

const route = useRoute();
const router = useRouter();
const game = computed(() => getGame(route.params.id));
const isOwner = computed(() => !!store.user && !!game.value && store.user.name === game.value.creator);
const isModerator = computed(() => !!store.user && !!store.user.is_moderator);

onMounted(async () => {
  if (game.value?.supabase_id) {
    if (!game.value.comments || game.value.comments.length === 0) {
      await loadGameComments(game.value.id);
    }
    if (!game.value.ratings || game.value.ratings.length === 0) {
      await loadGameRatings(game.value.id);
    }
  }
});

const isDeleting = ref(false);
async function onDelete() {
  if (!game.value || isDeleting.value) return;
  if (!confirm('确定删除该游戏？此操作不可撤销')) return;
  try {
    isDeleting.value = true;
    const ok = await deleteMyGame(game.value.id);
    if (ok) {
      router.push('/profile');
    } else {
      alert('删除失败，请稍后再试');
    }
  } finally {
    isDeleting.value = false;
  }
}

// 图片画廊
const galleryImages = computed(() => {
  const g = game.value?.gallery || [];
  
  if (g.length > 0) {
    return g;
  }
  
  const gameId = game.value?.id || 'default';
  const sampleImages = getGalleryImages(gameId);
  
  if (game.value?.cover) {
    return [game.value.cover, ...sampleImages.slice(1)];
  }
  
  return sampleImages;
});

// 评分系统
const hover = ref(0);
const userRating = computed(() => getUserRating(game.value?.id));
const averageRating = computed(() => getAverageStars(game.value) || 0);
const totalRatings = computed(() => Array.isArray(game.value?.ratings) ? game.value.ratings.length : 0);

function rate(n) {
  if (!game.value) return;
  if (!store.user?.id) { alert('请先登录'); router.push({ name: 'auth', query: { redirect: route.fullPath } }); return; }
  addRating(game.value.id, n);
}

function withdrawRating() {
  if (!game.value) return;
  withdrawUserRating(game.value.id);
}

// 评论系统
const comments = computed(() => game.value?.comments || []);
const isWithdrawingComment = ref(false);
function canWithdrawComment(c){
  if (!store.user) return false;
  if (store.user.is_moderator) return true;
  return (c.author_id && store.user.id && c.author_id === store.user.id);
}
async function withdrawComment(c){
  if (!game.value || !c) return;
  if (!store.user?.id) { alert('请先登录'); router.push({ name: 'auth', query: { redirect: route.fullPath } }); return; }
  if (!canWithdrawComment(c)) { alert('无权撤回该评论'); return; }
  if (!confirm('确认撤回这条评论？')) return;
  try {
    isWithdrawingComment.value = true;
    const ok = await deleteGameComment(game.value.id, c.id);
    if (!ok) alert('撤回失败，请稍后再试');
  } finally {
    isWithdrawingComment.value = false;
  }
}

const newComment = reactive({
  author: '',
  content: ''
});

const canSubmit = computed(() => {
  return newComment.content.trim().length > 0 && newComment.author.trim().length > 0;
});

function submitComment() {
  if (!canSubmit.value || !game.value) return;
  if (!store.user?.id) { alert('请先登录'); router.push({ name: 'auth', query: { redirect: route.fullPath } }); return; }
  
  const commentData = {
    author: newComment.author.trim(),
    content: newComment.content.trim()
  };
  
  const ok = addGameComment(game.value.id, commentData);
  if (!ok) return;
  
  // 重置表单
  newComment.author = '';
  newComment.content = '';
}

function likeComment(commentId) {
  if (!game.value) return;
  if (!store.user?.id) { alert('请先登录'); router.push({ name: 'auth', query: { redirect: route.fullPath } }); return; }
  likeGameComment(game.value.id, commentId);
}

function formatTime(timestamp) {
  const date = new Date(timestamp);
  const now = new Date();
  const diff = now - date;
  
  if (diff < 60000) return '刚刚';
  if (diff < 3600000) return `${Math.floor(diff / 60000)}分钟前`;
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}小时前`;
  if (diff < 2592000000) return `${Math.floor(diff / 86400000)}天前`;
  
  return date.toLocaleDateString();
}

function formatDate(timestamp) {
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}年${month}月${day}日`;
}

// 计算评测状态（基于平均评分）
function getReviewStatus() {
  if (totalRatings.value === 0) {
    return '无评测';
  }
  const avg = averageRating.value;
  // 根据Steam评测标准
  if (avg >= 4.5) {
    return '特别好评';
  } else if (avg >= 4.0) {
    return '好评';
  } else if (avg >= 3.5) {
    return '多半好评';
  } else if (avg >= 3.0) {
    return '褒贬不一';
  } else if (avg >= 2.5) {
    return '多半差评';
  } else {
    return '差评';
  }
}
</script>

<style scoped>
/* 页面容器 - 增加两边留白 */
.panel {
  max-width: 980px !important;
  margin: 0 auto;
  padding: 24px 32px !important;
}

/* Steam风格布局 */
.game-header {
  margin-bottom: 20px;
}

.game-header h2 {
  font-size: 32px;
  font-weight: 300;
  color: #fff;
  margin: 0;
  line-height: 1.2;
}

.steam-layout {
  display: grid;
  grid-template-columns: 616px 1fr;
  gap: 20px;
  margin-bottom: 32px;
}

.left-side {
  min-width: 0;
}

.right-side {
  min-width: 0;
}

/* 游戏信息卡片 */
.game-info-box {
  background: linear-gradient(to bottom, rgba(0,0,0,0.2) 0%, rgba(0,0,0,0.5) 100%);
  border-radius: 4px;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.game-description {
  font-size: 14px;
  line-height: 1.6;
  color: #acb2b8;
  margin-bottom: 16px;
}

.game-description p {
  margin: 0 0 12px 0;
}

.game-description p:last-child {
  margin-bottom: 0;
}

/* 游戏详细信息 */
.game-details {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 16px 0;
  border-top: 1px solid rgba(255, 255, 255, 0.1);
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}

.detail-row {
  display: flex;
  font-size: 13px;
  line-height: 1.6;
  margin-bottom: 6px;
}

.detail-label {
  color: #556772;
  width: 100px;
  flex-shrink: 0;
  font-weight: normal;
}

.detail-value {
  color: #acb2b8;
  flex: 1;
}

.review-badge {
  color: #66c0f4;
  font-weight: normal;
}

.review-count {
  color: #acb2b8;
}

.detail-link {
  color: #67c1f5;
  cursor: pointer;
}

.detail-link:hover {
  color: #fff;
}

.badge-tag {
  display: inline-block;
  background: rgba(103, 193, 245, 0.2);
  color: #67c1f5;
  padding: 2px 8px;
  border-radius: 2px;
  font-size: 11px;
  margin-right: 4px;
}

/* 游戏标签 */
.game-tags {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-top: 16px;
}

.label-text {
  font-size: 12px;
  color: #556772;
  margin-bottom: 10px;
}

.tags-list {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.tag-btn {
  background: rgba(103, 193, 245, 0.2);
  color: #67c1f5;
  border: none;
  padding: 5px 10px;
  border-radius: 2px;
  font-size: 12px;
  cursor: pointer;
  transition: all 0.2s ease;
  font-weight: normal;
  line-height: 1.4;
}

.tag-btn:hover {
  background: rgba(103, 193, 245, 0.3);
  color: #fff;
}

/* 访问官网按钮区域 */
.purchase-area {
  margin-top: auto;
  padding-top: 20px;
}

.official-site-btn {
  display: block;
  background: linear-gradient(to bottom, #75b022 5%, #588a1b 95%);
  color: white;
  text-decoration: none;
  padding: 14px;
  border-radius: 4px;
  text-align: center;
  font-size: 15px;
  font-weight: 500;
  transition: all 0.2s ease;
  border: none;
  cursor: pointer;
  width: 100%;
}

.official-site-btn:hover {
  background: linear-gradient(to bottom, #8bc53f 5%, #75b022 95%);
}

.muted { color: var(--muted); }
.text { white-space: pre-wrap; line-height: 1.7; }
.actions { margin-top: 24px; display: flex; gap: 8px; }

/* 评分系统 */
.rating-section {
  margin: 24px 0;
  padding: 20px;
  background: #0b1020;
  border: 1px solid var(--border);
  border-radius: 12px;
}

.rating-container {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.stars-display {
  padding-bottom: 16px;
  border-bottom: 1px solid var(--border);
}

.stars-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.rating-label {
  color: var(--muted);
  font-size: 14px;
  min-width: 60px;
}

.stars-avg {
  display: flex;
  gap: 2px;
}

.star {
  color: #64748b;
  font-size: 18px;
}

.star.filled {
  color: #f59e0b;
}

.rating-text {
  color: var(--muted);
  font-size: 14px;
}

.user-rating {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.rating-input {
  display: flex;
  align-items: center;
  gap: 12px;
}

.stars-input {
  display: flex;
  gap: 4px;
}

.star-btn {
  background: transparent;
  border: none;
  color: #64748b;
  font-size: 22px;
  cursor: pointer;
  transition: all 0.2s ease;
  padding: 4px;
  border-radius: 4px;
}

.star-btn:hover {
  transform: scale(1.1);
  color: #fbbf24;
}

.star-btn.active {
  color: #f59e0b;
}

.star-btn.user-rated {
  color: #f59e0b;
  background: rgba(245, 158, 11, 0.1);
}

.btn-withdraw {
  background: #dc2626;
  color: white;
  border: none;
  padding: 6px 12px;
  border-radius: 6px;
  font-size: 12px;
  cursor: pointer;
  transition: background 0.2s ease;
}

.btn-withdraw:hover {
  background: #b91c1c;
}

.user-rating-text {
  color: #f59e0b;
  font-size: 14px;
  font-weight: 500;
}

/* 评论区 */
.comments-section {
  margin: 24px 0;
}

.comments-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--border);
}

.comments-count {
  color: var(--muted);
  font-size: 14px;
}

/* 评论表单 */
.comment-form {
  background: #0b1020;
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 16px;
  margin-bottom: 20px;
}

.form-header {
  display: flex;
  gap: 12px;
  margin-bottom: 12px;
}

.user-avatar, .comment-avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  overflow: hidden;
  flex-shrink: 0;
}

.avatar-placeholder {
  width: 100%;
  height: 100%;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-weight: bold;
  font-size: 16px;
}

.form-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.author-input {
  background: #1a1f2e;
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 8px 12px;
  color: white;
  font-size: 14px;
}


.comment-textarea {
  width: 100%;
  background: #1a1f2e;
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 12px;
  color: white;
  font-size: 14px;
  line-height: 1.5;
  resize: vertical;
  min-height: 80px;
}

.form-actions {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 12px;
}

.char-count {
  color: var(--muted);
  font-size: 12px;
}

.btn-submit {
  background: #3b82f6;
  color: white;
  border: none;
  padding: 8px 16px;
  border-radius: 6px;
  font-size: 14px;
  cursor: pointer;
  transition: background 0.2s ease;
}

.btn-submit:hover:not(:disabled) {
  background: #2563eb;
}

.btn-submit:disabled {
  background: #374151;
  cursor: not-allowed;
}

/* 评论列表 */
.comments-list {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.comment-item {
  background: #0b1020;
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 16px;
}

.comment-header {
  display: flex;
  gap: 12px;
  margin-bottom: 12px;
}

.comment-info {
  flex: 1;
}

.comment-author {
  font-weight: 600;
  color: white;
  margin-bottom: 4px;
}

.comment-rating {
  display: flex;
  gap: 2px;
  margin-bottom: 4px;
}

.comment-star {
  color: #64748b;
  font-size: 14px;
}

.comment-star.filled {
  color: #f59e0b;
}

.comment-time {
  color: var(--muted);
  font-size: 12px;
}

.comment-content {
  color: #e2e8f0;
  line-height: 1.6;
  margin-bottom: 12px;
  white-space: pre-wrap;
}

.comment-actions {
  display: flex;
  gap: 16px;
}

.action-btn {
  background: transparent;
  border: none;
  color: var(--muted);
  font-size: 12px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 4px 8px;
  border-radius: 4px;
  transition: all 0.2s ease;
}

.action-btn:hover {
  background: rgba(255, 255, 255, 0.05);
  color: white;
}

.action-icon {
  font-size: 14px;
}

.empty-comments {
  text-align: center;
  color: var(--muted);
  padding: 40px 20px;
  background: #0b1020;
  border: 1px solid var(--border);
  border-radius: 12px;
}

/* 响应式设计 */
@media (max-width: 1024px) {
  .steam-layout {
    grid-template-columns: 1fr;
    gap: 20px;
  }

  .left-side {
    order: 1;
  }

  .right-side {
    order: 2;
  }

  .game-info-box {
    height: auto;
  }
}

@media (max-width: 768px) {
  .game-header h2 {
    font-size: 22px;
  }

  .steam-layout {
    gap: 16px;
  }

  .game-info-box {
    padding: 12px;
  }

  .detail-label {
    width: 80px;
    font-size: 11px;
  }

  .detail-value {
    font-size: 11px;
  }

  .price-value {
    font-size: 18px;
  }

  .grid.cols-2 {
    grid-template-columns: 1fr;
    gap: 20px;
  }
  
  .stars-row {
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }
  
  .rating-input {
    flex-wrap: wrap;
  }
  
  .form-header {
    flex-direction: column;
    gap: 8px;
  }
  
  .comments-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }
}

@media (max-width: 480px) {
  .game-header h2 {
    font-size: 18px;
  }

  .game-description {
    font-size: 12px;
  }

  .tags-list {
    gap: 4px;
  }

  .tag-btn {
    font-size: 10px;
    padding: 4px 8px;
  }
}
.blocking-modal {
  position: fixed; inset: 0;
  background: rgba(0,0,0,0.4);
  display: flex; align-items: center; justify-content: center;
  color: #fff; font-size: 16px; z-index: 9999;
}
</style>