// Recipe.ets - 配方数据模型

/**
 * 配料接口
 */
export interface Ingredient {
  id?: string;
  cocktail_id?: string;
  name: string;
  volume: number;
  abv?: number;
}

/**
 * 配方接口
 */
export interface Recipe {
  id: string;
  name: string;
  createdBy: string;
  instructions?: string;
  estimatedAbv: number;
  likeCount: number;
  favoriteCount: number;
  isLiked?: boolean;
  isFavorited?: boolean;
  ingredients?: string | Array<Ingredient>; // 列表接口返回string(逗号分隔),详情接口返回array
}

/**
 * 配方列表响应接口
 */
export interface RecipesResponse {
  recipes: Array<Recipe>;
  totalPages: number;
  currentPage: number;
  sortBy: string;
}

/**
 * 配方交互状态接口
 */
export interface RecipeInteractions {
  likeCount: number;
  favoriteCount: number;
  isLiked: boolean;
  isFavorited: boolean;
}

/**
 * 推荐配方接口
 */
export interface RecommendedRecipe {
  id: string;
  name: string;
  estimatedAbv: number | string; // 后端返回字符串类型
  matchPercentage: number; // 匹配度百分比 (0-100)
  reason: string; // 合并的推荐理由
  reasons: Array<string>; // 推荐理由数组
  likeCount: number; // 点赞数
}

/**
 * 推荐响应接口
 */
interface GeneratedTypeLiteralInterface_1 {
  currentPage: number;
  totalPages: number;
  totalRecommendations: number;
  limit: number;
  hasMore: boolean;
}

export interface RecommendationsResponse {
  recommendations: Array<RecommendedRecipe>;
  message?: string; // 当无推荐时的提示信息
  pagination?: GeneratedTypeLiteralInterface_1;
}
