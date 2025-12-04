// Recipe.ets - 配方数据模型

/**
 * API配料接口 (用于API响应)
 */
export interface APIIngredient {
  id: string;
  cocktail_id?: string;
  name: string;
  volume: number;
  abv: number;
}

/**
 * 配料接口 (通用)
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
  category?: string;
  difficulty?: string;
  preparationTime?: number;
  createdAt?: string;
}

/**
 * 评论接口
 */
export interface Comment {
  id: string;
  user_id: string;
  username: string;
  text: string;
  timestamp: string;
}

/**
 * 用户接口
 */
export interface User {
  id: string;
  username: string;
  role: string;
  email?: string;
  createdAt?: string;
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
 * 配方推荐接口 (用于推荐API响应)
 */
export interface RecipeRecommendation {
  id: string;
  name: string;
  estimatedAbv: number;
  matchPercentage: number;
  reason: string;
  reasons: string[];
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
 * API通用响应接口
 */
export interface APIResponse<T> {
  success?: boolean;
  message?: string;
  data?: T;
  recipes?: Recipe[];
  totalPages?: number;
  currentPage?: number;
  sortBy?: string;
  recommendations?: RecipeRecommendation[];
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

/**
 * 认证状态接口
 */
export interface AuthStatus {
  loggedIn: boolean;
  username?: string;
  role?: string;
}

/**
 * 自定义鸡尾酒接口
 */
export interface CustomCocktail {
  id: string;
  name: string;
  ingredients?: APIIngredient[];
  steps?: string[];
  estimatedAbv?: number;
  creator?: string;
}

/**
 * 生成的鸡尾酒接口
 */
export interface GeneratedCocktail {
  name: string;
  ingredients: GeneratedIngredient[];
  steps: string[];
  estimatedAbv?: number;
}

/**
 * 生成的配料接口
 */
export interface GeneratedIngredient {
  name: string;
  volume?: number;
  abv?: number;
}

/**
 * 管理员统计接口
 */
export interface AdminStats {
  totalRecipes: number;
  totalUsers: number;
  visits: Record<string, number>;
}

/**
 * 风味分析结果接口
 */
export interface FlavorAnalysisResult {
  analysis: string;
  analyzedAt: Date;
}
