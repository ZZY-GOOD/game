<template>
  <div class="steam-carousel">
    <div class="carousel-container" v-if="currentGame">
      <!-- 左侧：大图封面 -->
      <div class="left-cover" @click="goToGame(currentGame.id)">
        <img :src="getCoverImage(currentGame)" :alt="currentGame.title" />
      </div>

      <!-- 右侧：游戏信息 -->
      <div class="right-info">
        <!-- 游戏标题 -->
        <div class="game-title">
          <h2>{{ currentGame.title }}</h2>
        </div>

        <!-- 四格小图 -->
        <div class="gallery-grid">
          <div 
            v-for="(img, idx) in getGalleryImages(currentGame)" 
            :key="idx"
            class="gallery-item"
            @click="goToGame(currentGame.id)"
          >
            <img :src="img" :alt="`${currentGame.title} 截图 ${idx + 1}`" />
          </div>
        </div>

        <!-- 游戏标签 -->
        <div class="game-tags" v-if="currentGame.genres && currentGame.genres.length">
          <button 
            v-for="tag in currentGame.genres.slice(0, 4)" 
            :key="tag"
            class="tag-btn"
          >
            {{ tag }}
          </button>
        </div>

        <!-- 最近评测 -->
        <div class="game-review">
          <span class="review-label">最近评测：</span>
          <span class="review-status">{{ getReviewStatus(currentGame) }}</span>
          <span class="review-count">({{ getRatingCount(currentGame) }})</span>
        </div>

        <!-- 价格信息 -->
        <div class="game-price">
          <span class="price-label">¥ {{ currentGame.price || 0 }}</span>
        </div>
      </div>

      <!-- 导航箭头（整个轮播两侧） -->
      <button class="nav-arrow prev" @click.stop="prev" v-if="games.length > 1">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
          <polyline points="15 18 9 12 15 6"></polyline>
        </svg>
      </button>
      <button class="nav-arrow next" @click.stop="next" v-if="games.length > 1">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
          <polyline points="9 18 15 12 9 6"></polyline>
        </svg>
      </button>
    </div>

    <!-- 底部指示器 -->
    <div class="carousel-indicators" v-if="games.length > 1">
      <button
        v-for="(game, idx) in games"
        :key="game.id"
        class="indicator"
        :class="{ active: idx === currentIndex }"
        @click="goTo(idx)"
      ></button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';

const props = defineProps({
  games: {
    type: Array,
    default: () => []
  },
  autoplay: {
    type: Boolean,
    default: true
  },
  interval: {
    type: Number,
    default: 5000
  }
});

const router = useRouter();
const currentIndex = ref(0);
let autoplayTimer = null;

const currentGame = computed(() => {
  if (props.games.length === 0) return null;
  return props.games[currentIndex.value];
});

// 获取封面图片
function getCoverImage(game) {
  if (game.cover) return game.cover;
  if (game.gallery && game.gallery.length > 0) return game.gallery[0];
  return makePlaceholder(game.title);
}

// 获取轮播小图（最多4张）
function getGalleryImages(game) {
  const images = [];
  
  // 优先使用 gallery
  if (game.gallery && game.gallery.length > 0) {
    images.push(...game.gallery.slice(0, 4));
  }
  
  // 如果不足4张，用封面补充
  while (images.length < 4) {
    if (game.cover && !images.includes(game.cover)) {
      images.push(game.cover);
    } else {
      images.push(makePlaceholder(game.title, images.length));
    }
  }
  
  return images.slice(0, 4);
}

// 生成占位图
function makePlaceholder(title, index = 0) {
  const colors = ['#1a2332', '#2a3342', '#1a2842', '#2a3852'];
  const bg = colors[index % colors.length];
  return `data:image/svg+xml;utf8,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="225">
      <rect width="100%" height="100%" fill="${bg}"/>
      <text x="50%" y="50%" text-anchor="middle" dominant-baseline="middle" 
            fill="#6b7280" font-size="20" font-family="sans-serif">${title || '游戏'}</text>
    </svg>`
  )}`;
}

function next() {
  if (props.games.length === 0) return;
  currentIndex.value = (currentIndex.value + 1) % props.games.length;
}

function prev() {
  if (props.games.length === 0) return;
  currentIndex.value = (currentIndex.value - 1 + props.games.length) % props.games.length;
}

function goTo(index) {
  currentIndex.value = index;
}

function goToGame(gameId) {
  if (gameId) {
    router.push(`/game/${gameId}`);
  }
}

// 获取评分数量
function getRatingCount(game) {
  if (!game) return 0;
  if (typeof game.count === 'number') return game.count;
  if (Array.isArray(game.ratings)) return game.ratings.length;
  return 0;
}

// 获取平均评分
function getAverageRating(game) {
  if (!game) return 0;
  if (typeof game.avg === 'number') return game.avg;
  if (Array.isArray(game.ratings) && game.ratings.length > 0) {
    const sum = game.ratings.reduce((acc, r) => acc + (Number(r.rating ?? r.stars) || 0), 0);
    return Math.round((sum / game.ratings.length) * 10) / 10;
  }
  return 0;
}

// 计算评测状态
function getReviewStatus(game) {
  const count = getRatingCount(game);
  if (count === 0) return '无评测';
  
  const avg = getAverageRating(game);
  if (avg >= 4.5) return '特别好评';
  if (avg >= 4.0) return '好评';
  if (avg >= 3.5) return '多半好评';
  if (avg >= 3.0) return '褒贬不一';
  if (avg >= 2.5) return '多半差评';
  return '差评';
}

function startAutoplay() {
  if (!props.autoplay || props.games.length <= 1) return;
  stopAutoplay();
  autoplayTimer = setInterval(next, props.interval);
}

function stopAutoplay() {
  if (autoplayTimer) {
    clearInterval(autoplayTimer);
    autoplayTimer = null;
  }
}

onMounted(() => {
  startAutoplay();
});

onBeforeUnmount(() => {
  stopAutoplay();
});
</script>

<style scoped>
.steam-carousel {
  width: 100%;
  max-width: 1200px;
  margin: 0 auto;
  padding: 0;
}

.carousel-container {
  position: relative;
  display: grid;
  grid-template-columns: 656px 1fr;
  gap: 12px;
  background: linear-gradient(to bottom, rgba(0,0,0,0.2) 0%, rgba(0,0,0,0.5) 100%);
  border-radius: 4px;
  overflow: visible;
  padding: 8px;
  margin: 0 40px 16px 40px;
}

/* 左侧封面 */
.left-cover {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 9;
  background: #000;
  border-radius: 3px;
  overflow: hidden;
  cursor: pointer;
}

.left-cover img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

/* 导航箭头 - 位于整个轮播两侧 */
.nav-arrow {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  background: rgba(0, 0, 0, 0.5);
  border: 1px solid rgba(255, 255, 255, 0.1);
  color: white;
  width: 32px;
  height: 69px;
  border-radius: 3px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
  z-index: 10;
}

.nav-arrow:hover {
  background: rgba(0, 0, 0, 0.7);
  border-color: rgba(255, 255, 255, 0.3);
}

.nav-arrow.prev {
  left: -40px;
}

.nav-arrow.next {
  right: -40px;
}

/* 右侧信息 */
.right-info {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
  padding: 2px 4px;
}

.game-title {
  margin-bottom: 2px;
}

.game-title h2 {
  font-size: 18px;
  font-weight: 300;
  color: #fff;
  margin: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  line-height: 1.2;
}

/* 四格小图 - 缩小尺寸 */
.gallery-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 4px;
}

.gallery-item {
  width: 100%;
  aspect-ratio: 16 / 9;
  background: #000;
  border-radius: 3px;
  overflow: hidden;
  cursor: pointer;
  transition: all 0.2s ease;
}

.gallery-item:hover {
  transform: scale(1.02);
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.4);
}

.gallery-item img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

/* 游戏标签 */
.game-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 4px;
}

.tag-btn {
  background: rgba(103, 193, 245, 0.2);
  color: #67c1f5;
  border: none;
  padding: 2px 7px;
  border-radius: 2px;
  font-size: 10px;
  cursor: pointer;
  transition: all 0.2s ease;
  line-height: 1.3;
}

.tag-btn:hover {
  background: rgba(103, 193, 245, 0.3);
}

/* 最近评测 */
.game-review {
  font-size: 11px;
  color: #acb2b8;
  margin-top: 4px;
  line-height: 1.4;
}

.review-label {
  color: #556772;
}

.review-status {
  color: #66c0f4;
  margin-left: 4px;
}

.review-count {
  color: #acb2b8;
  margin-left: 2px;
}

/* 价格 */
.game-price {
  margin-top: auto;
  padding-top: 4px;
}

.price-label {
  font-size: 14px;
  color: #acb2b8;
  font-weight: normal;
}

/* 底部指示器 */
.carousel-indicators {
  display: flex;
  justify-content: center;
  gap: 8px;
  padding: 12px 0;
}

.indicator {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  border: none;
  background: rgba(255, 255, 255, 0.3);
  cursor: pointer;
  transition: all 0.3s ease;
  padding: 0;
}

.indicator:hover {
  background: rgba(255, 255, 255, 0.6);
  transform: scale(1.2);
}

.indicator.active {
  background: #ffffff;
  transform: scale(1.3);
}

/* 响应式 */
@media (max-width: 1024px) {
  .carousel-container {
    grid-template-columns: 1fr;
    gap: 12px;
    margin: 0 0 16px 0;
  }

  .nav-arrow {
    display: none;
  }

  .game-title h2 {
    font-size: 18px;
  }
}

@media (max-width: 768px) {
  .carousel-container {
    padding: 8px;
  }

  .gallery-grid {
    gap: 4px;
  }

  .game-title h2 {
    font-size: 16px;
  }

  .price-label {
    font-size: 12px;
  }
  
  .tag-btn {
    font-size: 9px;
    padding: 2px 6px;
  }

  .game-review {
    font-size: 10px;
  }
}
</style>

