<template>
  <div class="steam-carousel">
    <!-- 主图显示区域 -->
    <div class="main-image-wrapper">
      <div class="main-image" v-if="currentImage">
        <img 
          :src="currentImage" 
          :alt="`游戏截图 ${currentIndex + 1}`"
        />
        <!-- 左右导航箭头 -->
        <button 
          v-if="images.length > 1"
          class="nav-arrow nav-left" 
          @click="prev"
          aria-label="上一张"
        >
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="15 18 9 12 15 6"></polyline>
          </svg>
        </button>
        <button 
          v-if="images.length > 1"
          class="nav-arrow nav-right" 
          @click="next"
          aria-label="下一张"
        >
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="9 18 15 12 9 6"></polyline>
          </svg>
        </button>
      </div>
      <div v-else class="no-image">
        <span>暂无图片</span>
      </div>
    </div>

    <!-- 缩略图条 -->
    <div class="thumbnails-bar" v-if="images.length > 1">
      <button 
        class="thumb-nav thumb-prev"
        @click="scrollThumbs('left')"
        :disabled="thumbScrollPos <= 0"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
          <polyline points="15 18 9 12 15 6"></polyline>
        </svg>
      </button>

      <div class="thumbnails-container" ref="thumbContainer">
        <div class="thumbnails-track" ref="thumbTrack">
          <button
            v-for="(img, idx) in images"
            :key="idx"
            class="thumbnail"
            :class="{ active: idx === currentIndex }"
            @click="goTo(idx)"
          >
            <img :src="img" :alt="`缩略图 ${idx + 1}`" />
          </button>
        </div>
      </div>

      <button 
        class="thumb-nav thumb-next"
        @click="scrollThumbs('right')"
        :disabled="isThumbScrollEnd"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
          <polyline points="9 18 15 12 9 6"></polyline>
        </svg>
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';

const props = defineProps({
  images: {
    type: Array,
    default: () => []
  }
});

const currentIndex = ref(0);
const thumbScrollPos = ref(0);
const thumbContainer = ref(null);
const thumbTrack = ref(null);

const currentImage = computed(() => {
  if (props.images.length === 0) return null;
  return props.images[currentIndex.value];
});

const isThumbScrollEnd = computed(() => {
  if (!thumbContainer.value || !thumbTrack.value) return false;
  const container = thumbContainer.value;
  const track = thumbTrack.value;
  return thumbScrollPos.value >= track.scrollWidth - container.clientWidth;
});

function next() {
  if (props.images.length === 0) return;
  currentIndex.value = (currentIndex.value + 1) % props.images.length;
  scrollToActiveThumbnail();
}

function prev() {
  if (props.images.length === 0) return;
  currentIndex.value = (currentIndex.value - 1 + props.images.length) % props.images.length;
  scrollToActiveThumbnail();
}

function goTo(index) {
  currentIndex.value = index;
  scrollToActiveThumbnail();
}

function scrollThumbs(direction) {
  if (!thumbContainer.value) return;
  const scrollAmount = 200;
  if (direction === 'left') {
    thumbScrollPos.value = Math.max(0, thumbScrollPos.value - scrollAmount);
  } else {
    const maxScroll = thumbTrack.value.scrollWidth - thumbContainer.value.clientWidth;
    thumbScrollPos.value = Math.min(maxScroll, thumbScrollPos.value + scrollAmount);
  }
  thumbContainer.value.scrollTo({
    left: thumbScrollPos.value,
    behavior: 'smooth'
  });
}

function scrollToActiveThumbnail() {
  if (!thumbContainer.value || !thumbTrack.value) return;
  const activeThumb = thumbTrack.value.children[currentIndex.value];
  if (!activeThumb) return;

  const containerRect = thumbContainer.value.getBoundingClientRect();
  const thumbRect = activeThumb.getBoundingClientRect();

  if (thumbRect.left < containerRect.left) {
    thumbScrollPos.value = activeThumb.offsetLeft - 10;
    thumbContainer.value.scrollTo({
      left: thumbScrollPos.value,
      behavior: 'smooth'
    });
  } else if (thumbRect.right > containerRect.right) {
    thumbScrollPos.value = activeThumb.offsetLeft - thumbContainer.value.clientWidth + activeThumb.offsetWidth + 10;
    thumbContainer.value.scrollTo({
      left: thumbScrollPos.value,
      behavior: 'smooth'
    });
  }
}

// 键盘导航
function handleKeydown(e) {
  if (e.key === 'ArrowLeft') {
    prev();
  } else if (e.key === 'ArrowRight') {
    next();
  }
}

onMounted(() => {
  window.addEventListener('keydown', handleKeydown);
});

onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleKeydown);
});

watch(() => props.images, () => {
  currentIndex.value = 0;
  thumbScrollPos.value = 0;
}, { deep: true });
</script>

<style scoped>
.steam-carousel {
  width: 100%;
}

/* 主图区域 */
.main-image-wrapper {
  width: 100%;
  margin-bottom: 10px;
  border-radius: 4px;
  overflow: hidden;
  background: #000;
}

.main-image {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 9;
  background: #000;
  display: flex;
  align-items: center;
  justify-content: center;
}

.main-image img {
  width: 100%;
  height: 100%;
  object-fit: contain;
  display: block;
}

.no-image {
  aspect-ratio: 16 / 9;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #666;
  background: #1a1a1a;
}

/* 导航箭头 */
.nav-arrow {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  background: rgba(0, 0, 0, 0.5);
  border: none;
  color: white;
  width: 48px;
  height: 48px;
  border-radius: 4px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
  opacity: 0;
  z-index: 10;
}

.main-image:hover .nav-arrow {
  opacity: 1;
}

.nav-arrow:hover {
  background: rgba(0, 0, 0, 0.7);
}

.nav-left {
  left: 10px;
}

.nav-right {
  right: 10px;
}

/* 缩略图条 */
.thumbnails-bar {
  display: flex;
  align-items: center;
  gap: 6px;
}

.thumb-nav {
  flex-shrink: 0;
  width: 32px;
  height: 69px;
  background: rgba(0, 0, 0, 0.3);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 3px;
  color: white;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}

.thumb-nav:hover:not(:disabled) {
  background: rgba(0, 0, 0, 0.5);
  border-color: rgba(255, 255, 255, 0.3);
}

.thumb-nav:disabled {
  opacity: 0.3;
  cursor: not-allowed;
}

.thumbnails-container {
  flex: 1;
  overflow: hidden;
  position: relative;
}

.thumbnails-track {
  display: flex;
  gap: 6px;
}

.thumbnail {
  flex-shrink: 0;
  width: 116px;
  height: 65px;
  padding: 0;
  border: 2px solid transparent;
  border-radius: 3px;
  overflow: hidden;
  background: #000;
  cursor: pointer;
  transition: all 0.2s ease;
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
}

.thumbnail::after {
  content: '';
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.3);
  transition: all 0.2s ease;
}

.thumbnail:hover::after {
  background: rgba(0, 0, 0, 0);
}

.thumbnail.active {
  border-color: #ffffff;
}

.thumbnail.active::after {
  background: rgba(0, 0, 0, 0);
}

.thumbnail img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

/* 响应式 */
@media (max-width: 768px) {
  .thumbnail {
    width: 90px;
    height: 50px;
  }

  .thumb-nav {
    width: 28px;
    height: 50px;
  }

  .nav-arrow {
    width: 40px;
    height: 40px;
  }
}
</style>

