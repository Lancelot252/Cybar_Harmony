// Recipe.ets - 配方数据模型

export interface APIIngredient {
  id: string;
  cocktail_id?: string;
  name: string;
  volume: number;
  abv: number;
}

export interface Recipe {
  id: string;
  name: string;
  instructions: string;
  estimatedAbv: number;
  createdBy: string;
  ingredients?: APIIngredient[];
  likeCount: number;
  favoriteCount: number;
  isLiked?: boolean;
  isFavorited?: boolean;
  category?: string;
  difficulty?: string;
  preparationTime?: number;
  createdAt?: string;
}

export interface Comment {
  id: string;
  user_id: string;
  username: string;
  text: string;
  timestamp: string;
}

export interface User {
  id: string;
  username: string;
  role: string;
  email?: string;
  createdAt?: string;
}

export interface RecipeInteractions {
  likeCount: number;
  favoriteCount: number;
  isLiked: boolean;
  isFavorited: boolean;
}

export interface RecipeRecommendation {
  id: string;
  name: string;
  estimatedAbv: number;
  matchPercentage: number;
  reason: string;
  reasons: string[];
}

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

export interface RecipesResponse {
  recipes: Array<object>;
  totalPages: number;
  currentPage: number;
  sortBy?: string;
}

export interface AuthStatus {
  loggedIn: boolean;
  username?: string;
  role?: string;
}

export interface CustomCocktail {
  id: string;
  name: string;
  ingredients?: APIIngredient[];
  steps?: string[];
  estimatedAbv?: number;
  creator?: string;
}

export interface GeneratedCocktail {
  name: string;
  ingredients: GeneratedIngredient[];
  steps: string[];
  estimatedAbv?: number;
}

export interface GeneratedIngredient {
  name: string;
  volume?: number;
  abv?: number;
}

export interface AdminStats {
  totalRecipes: number;
  totalUsers: number;
  visits: Record<string, number>;
}

export interface FlavorAnalysisResult {
  analysis: string;
  analyzedAt: Date;
}
