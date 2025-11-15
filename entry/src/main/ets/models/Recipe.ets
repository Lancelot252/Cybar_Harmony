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
