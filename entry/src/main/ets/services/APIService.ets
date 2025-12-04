// APIService.ets - API服务封装
// 对应 Swift 项目中的 APIService.swift

import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { RecipesResponse } from '../common/models/Recipe';
import { RecommendationsResponse } from '../models/Recipe';


// 自定义错误类
export class APIError extends Error {
  code: string;
  
  constructor(message: string, code: string = 'UNKNOWN') {
    super(message);
    this.code = code;
    this.name = 'APIError';
  }
}

// API响应基础结构
export interface APIResponse<T> {
  success?: boolean;
  message?: string;
  data?: T;
}

// 用户信息
export interface User {
  id: string;
  username: string;
  role: string;
}

// 认证状态
export interface AuthStatus {
  loggedIn: boolean;
  username?: string;
  role?: string;
}

// 登录状态缓存结构
interface LoginCache {
  username: string;
  role: string;
  cachedAt: number;
  cookie?: string;
}

const LOGIN_CACHE_KEY = 'loginCache';
const LOGIN_CACHE_MAX_AGE_MS = 90 * 24 * 60 * 60 * 1000; // 90 天

interface LoginResponseData {
  username?: string;
  role?: string;
  userRole?: string;
}

interface LoginResponseBody {
  message?: string;
  data?: LoginResponseData;
  username?: string;
  role?: string;
  userRole?: string;
}

interface LoginRequestBody {
  username: string;
  password: string;
}

interface CommentRequestBody {
  commentText: string;
}

interface RequestHeaders {
  'Content-Type'?: string;
  Cookie?: string;
}

interface HeaderOptions {
  contentType?: string;
}

// 状态变化监听器类型
type StateChangeListener = () => void;

/**
 * ==================== 环境配置 ====================
 * 切换环境：注释/取消注释下面的 BASE_URL 即可
 * =================================================
 */

// ⚠️ 开发环境 - 本地调试（使用时取消注释这行，注释掉生产环境）
// const BASE_URL: string = 'http://172.26.19.215:8080';
// const BASE_URL: string = 'http://10.0.2.2:80';
const BASE_URL: string = 'http://192.168.43.231:8080';
// ⚠️ 生产环境 - 远程服务器（发布时取消注释这行，注释掉开发环境）
// const BASE_URL: string = 'http://47.101.11.98:8080';

/**
 * API服务单例类
 * 提供与后端交互的网络服务
 * 使用观察者模式通知UI更新
 */
export default class APIService {
  private static instance: APIService;
  
  // 使用配置的baseURL
  private baseURL: string = BASE_URL;
  private context?: common.UIAbilityContext;
  private preferences?: preferences.Preferences;
  private authCookie: string = '';
  private loginCache?: LoginCache;
  
  // 当前登录状态 - 私有,通过 getter 访问
  private _isLoggedIn: boolean = false;
  private _currentUser?: User;
  
  // 状态变化监听器列表
  private listeners: StateChangeListener[] = [];
  
  // 公开的 getter
  public get isLoggedIn(): boolean {
    return this._isLoggedIn;
  }
  
  public get currentUser(): User | undefined {
    return this._currentUser;
  }

  public get cachedLogin(): LoginCache | undefined {
    return this.loginCache;
  }
  
  private constructor() {
    // 私有构造函数,确保单例模式
  }
  
  /**
   * 获取APIService单例
   */
  public static getInstance(): APIService {
    if (!APIService.instance) {
      console.info('[APIService] Creating new APIService instance');
      APIService.instance = new APIService();
      console.info(`[APIService] Instance created - baseURL: ${APIService.instance.baseURL}`);
    }
    return APIService.instance;
  }
  
  /**
   * 添加状态变化监听器
   */
  public addListener(listener: StateChangeListener): void {
    this.listeners.push(listener);
  }
  
  /**
   * 移除状态变化监听器
   */
  public removeListener(listener: StateChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index > -1) {
      this.listeners.splice(index, 1);
    }
  }
  
  /**
   * 通知所有监听器状态已变化
   */
  private notifyListeners(): void {
    this.listeners.forEach(listener => listener());
  }
  
  /**
   * 更新登录状态并通知监听器
   */
  private updateLoginState(isLoggedIn: boolean, user?: User): void {
    this._isLoggedIn = isLoggedIn;
    this._currentUser = user;
    this.notifyListeners();
  }

  /**
   * 构建带有认证信息的请求头
   */
  private buildAuthHeaders(options?: HeaderOptions): RequestHeaders | undefined {
    const hasCookie = this.authCookie && this.authCookie.length > 0;
    const hasContentType = options && options.contentType && options.contentType.length > 0;

    if (!hasCookie && !hasContentType) {
      return undefined;
    }

    if (hasCookie && hasContentType) {
      return {
        'Content-Type': (options as HeaderOptions).contentType!,
        Cookie: this.authCookie
      };
    }

    if (hasContentType) {
      return {
        'Content-Type': (options as HeaderOptions).contentType!
      };
    }

    return {
      Cookie: this.authCookie
    };
  }

  private createRequestOptions(
    method: http.RequestMethod,
    headerOptions?: HeaderOptions,
    body?: Object
  ): http.HttpRequestOptions {
    const headers = this.buildAuthHeaders(headerOptions);
    const options: http.HttpRequestOptions = {
      method: method,
      expectDataType: http.HttpDataType.OBJECT
    };

    if (headers) {
      options.header = headers;
    }

    if (body) {
      options.extraData = body;
    }

    return options;
  }

  /**
   * 从响应头中提取服务端下发的会话 Cookie
   */
  private extractSessionCookie(response: http.HttpResponse): string | undefined {
    const headerObject: Object | undefined = response.header as Object;
    if (!headerObject) {
      return undefined;
    }

    const lowerCookie: ESObject = Reflect.get(headerObject, 'set-cookie') as ESObject;
    const upperCookie: ESObject = Reflect.get(headerObject, 'Set-Cookie') as ESObject;
    const normalized: ESObject = lowerCookie !== undefined ? lowerCookie : upperCookie;

    if (typeof normalized === 'string' && normalized.length > 0) {
      const parts = normalized.split(';');
      return parts.length > 0 ? parts[0] : normalized;
    }

    if (Array.isArray(normalized)) {
      const entries: Array<ESObject> = normalized as Array<ESObject>;
      const length = entries.length;
      for (let i = 0; i < length; i++) {
        const entry: ESObject = entries[i];
        if (typeof entry === 'string') {
          const entryStr: string = entry as string;
          if (entryStr.length > 0) {
            const parts = entryStr.split(';');
            return parts.length > 0 ? parts[0] : entryStr;
          }
        }
      }
    }

    return undefined;
  }
  
  /**
   * 初始化服务
   * @param context 应用上下文
   */
  public async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    
    // 初始化 preferences
    try {
      this.preferences = await preferences.getPreferences(context, 'apiservice');
    } catch (error) {
      console.error('[APIService] 初始化 preferences 失败:', error);
    }
    
    // 恢复本地登录状态缓存
    await this.restoreLoginFromCache();
    
    // 检查服务器状态
    await this.checkAuthStatus();
  }
  
  /**
   * 从本地缓存恢复登录状态
   */
  private async restoreLoginFromCache(): Promise<void> {
    if (!this.preferences) {
      return;
    }

    try {
      const cacheString = await this.preferences.get(LOGIN_CACHE_KEY, '') as string;
      if (!cacheString || cacheString.length === 0) {
        return;
      }

      const cache = JSON.parse(cacheString) as LoginCache | undefined;
      if (!cache) {
        return;
      }

      // 检查是否过期
      const now = Date.now();
      if (now - cache.cachedAt > LOGIN_CACHE_MAX_AGE_MS) {
        await this.clearLoginCache();
        return;
      }

      this.loginCache = cache;
      this.authCookie = cache.cookie ? cache.cookie : '';
      this.updateLoginState(true, {
        id: '',
        username: cache.username,
        role: cache.role
      });
    } catch (error) {
      console.error('[APIService] 恢复登录缓存失败:', error);
    }
  }

  /**
   * 持久化登录缓存
   */
  private async persistLoginCache(cache: LoginCache): Promise<void> {
    if (!this.preferences) {
      return;
    }

    try {
      this.loginCache = cache;
      this.authCookie = cache.cookie ? cache.cookie : '';
      await this.preferences.put(LOGIN_CACHE_KEY, JSON.stringify(cache));
      await this.preferences.flush();
    } catch (error) {
      console.error('[APIService] 保存登录缓存失败:', error);
    }
  }

  /**
   * 清除登录缓存
   */
  private async clearLoginCache(): Promise<void> {
    this.loginCache = undefined;
    this.authCookie = '';

    if (!this.preferences) {
      return;
    }

    try {
      await this.preferences.delete(LOGIN_CACHE_KEY);
      await this.preferences.flush();
    } catch (error) {
      console.error('[APIService] 清除登录缓存失败:', error);
    }
  }
  
  /**
   * 检查认证状态
   */
  public async checkAuthStatus(): Promise<void> {
    try {
      const url = `${this.baseURL}/api/auth/status`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200 && response.result) {
        const authStatus = response.result as AuthStatus;
        
        if (authStatus.loggedIn && authStatus.username && authStatus.role) {
          const user: User = {
            id: '',
            username: authStatus.username,
            role: authStatus.role
          };
          const cookie = this.extractSessionCookie(response);
          if (cookie && cookie.length > 0) {
            this.authCookie = cookie;
          }

          const cacheFromStatus: LoginCache = {
            username: authStatus.username,
            role: authStatus.role,
            cachedAt: Date.now(),
            cookie: this.authCookie
          };
          await this.persistLoginCache(cacheFromStatus);
          this.updateLoginState(true, user);
        } else {
          this.updateLoginState(false, undefined);
          await this.clearLoginCache();
        }
      }
    } catch (error) {
      console.error('[APIService] 检查认证状态失败:', error);
      if (!this.loginCache) {
        this.updateLoginState(false, undefined);
      }
    }
  }
  
  /**
   * 用户登录
   * @param username 用户名
   * @param password 密码
   */
  public async login(username: string, password: string): Promise<string> {
    try {
      const url = `${this.baseURL}/api/login`;
      const requestBody: LoginRequestBody = {
        username: username,
        password: password
      };
      const requestOptions = this.createRequestOptions(
        http.RequestMethod.POST,
        { contentType: 'application/json' },
        requestBody
      );
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        const result = response.result as LoginResponseBody | undefined;
        let resolvedUsername: string = username;
        let resolvedRole: string = '';
        let message: string = '登录成功';

        if (result) {
          if (result.message && result.message.length > 0) {
            message = result.message;
          }

          let payload: LoginResponseData | undefined = undefined;
          if (result.data) {
            payload = result.data;
          } else {
            const fallbackPayload: LoginResponseData = {
              username: result.username,
              role: result.role,
              userRole: result.userRole
            };
            payload = fallbackPayload;
          }

          if (payload) {
            if (payload.username && payload.username.length > 0) {
              resolvedUsername = payload.username;
            }
            const roleCandidate = payload.role && payload.role.length > 0 ? payload.role : (payload.userRole ? payload.userRole : '');
            if (roleCandidate && roleCandidate.length > 0) {
              resolvedRole = roleCandidate;
            }
          }
        }

        const user: User = {
          id: '',
          username: resolvedUsername,
          role: resolvedRole
        };

        const cookie = this.extractSessionCookie(response);
        this.authCookie = cookie ? cookie : '';
        const cacheFromLogin: LoginCache = {
          username: user.username,
          role: user.role,
          cachedAt: Date.now(),
          cookie: this.authCookie
        };
        await this.persistLoginCache(cacheFromLogin);
        this.updateLoginState(true, user);

        return message;
      } else {
        const errorBody = response.result as LoginResponseBody | undefined;
        let message = '登录失败';
        if (errorBody && errorBody.message && errorBody.message.length > 0) {
          message = errorBody.message;
        }
        throw new APIError(message, 'LOGIN_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 登录失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('登录请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 用户注册
   * @param username 用户名
   * @param password 密码
   */
  public async register(username: string, password: string): Promise<string> {
    try {
      const url = `${this.baseURL}/api/register`;
      const requestBody: LoginRequestBody = {
        username: username,
        password: password
      };
      const requestOptions = this.createRequestOptions(
        http.RequestMethod.POST,
        { contentType: 'application/json' },
        requestBody
      );
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 201) {
        return '注册成功';
      } else {
        const errorBody = response.result as LoginResponseBody | undefined;
        let message = '注册失败';
        if (errorBody && errorBody.message && errorBody.message.length > 0) {
          message = errorBody.message;
        }
        throw new APIError(message, 'REGISTER_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 注册失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('注册请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 用户登出
   */
  public async logout(): Promise<void> {
    try {
      const url = `${this.baseURL}/api/logout`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.POST);
      await http.createHttp().request(url, requestOptions);

      await this.clearLoginCache();
      this.authCookie = '';
      this.updateLoginState(false, undefined);
    } catch (error) {
      console.error('[APIService] 登出失败:', error);
      throw new APIError('登出请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 获取配方列表
   * @param page 页码
   * @param limit 每页数量
   * @param search 搜索关键词
   * @param sort 排序方式
   */
  public async fetchRecipes(
    page: number = 1,
    limit: number = 10,
    search: string = '',
    sort: string = 'default'
  ): Promise<object> {
    const httpRequest = http.createHttp();
    
    try {
      const url = `${this.baseURL}/api/recipes?page=${page}&limit=${limit}&search=${encodeURIComponent(search)}&sort=${sort}`;
      console.info(`[APIService] fetchRecipes - URL: ${url}`);
      
      // 配置请求选项 - 确保正确的超时和数据类型
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 10000,  // 10秒连接超时
        readTimeout: 10000      // 10秒读取超时
      };
      
      console.info(`[APIService] fetchRecipes - Sending request...`);
      const response = await httpRequest.request(url, requestOptions);
      
      console.info(`[APIService] fetchRecipes - Response code: ${response.responseCode}`);
      
      if (response.responseCode === 200) {
        const result = response.result as object;
        console.info(`[APIService] fetchRecipes - SUCCESS - Got ${Object.keys(result).length} keys`);
        
        const recipes = Reflect.get(result, 'recipes') as Array<object> | null;
        if (recipes && Array.isArray(recipes)) {
          console.info(`[APIService] fetchRecipes - Got ${recipes.length} recipes`);
        }
        
        return result;
      } else {
        console.error(`[APIService] fetchRecipes - HTTP Error ${response.responseCode}`);
        throw new APIError(`获取配方列表失败 (${response.responseCode})`, 'FETCH_FAILED');
      }
    } catch (error) {
      console.error('[APIService] fetchRecipes - Exception:', error);
      
      if (error instanceof APIError) {
        throw error;
      }
      
      // 处理网络错误
      throw new APIError('网络请求失败，请检查网络连接', 'NETWORK_ERROR');
    } finally {
      // 清理HTTP连接
      httpRequest.destroy();
    }
  }
  
  /**
   * 获取配方详情
   * @param id 配方ID
   * 对应 server.js: GET /api/recipes/:id
   */
  public async fetchRecipeDetail(id: string): Promise<object> {
    try {
      const url = `${this.baseURL}/api/recipes/${id}`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        return response.result as object;
      } else {
        throw new APIError('获取配方详情失败', 'FETCH_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 获取配方详情失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('获取配方详情请求失败', 'NETWORK_ERROR');
    }
  }

  /**
   * 获取配方交互状态 (点赞和收藏)
   * @param recipeId 配方ID
   * 对应 server.js: GET /api/recipes/:id/interactions
   */
  public async fetchRecipeInteractionStatus(recipeId: string): Promise<object> {
    try {
      const url = `${this.baseURL}/api/recipes/${recipeId}/interactions`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        return response.result as object;
      } else {
        throw new APIError('获取交互状态失败', 'FETCH_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 获取交互状态失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('获取交互状态请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 获取推荐列表（支持分页）
   * @param page 页码（从1开始）
   * @param limit 每页数量
   */
  public async fetchRecommendations(page: number = 1, limit: number = 10): Promise<RecommendationsResponse> {
    try {
      const url = `${this.baseURL}/api/recommendations?page=${page}&limit=${limit}`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        // expectDataType: OBJECT 已经自动解析为对象，无需 JSON.parse()
        const result = response.result as RecommendationsResponse;
        console.info(`[APIService] 推荐加载成功: 第${page}页, ${result.recommendations?.length || 0}条`);
        return result;
      } else {
        throw new APIError('获取推荐列表失败', 'FETCH_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 获取推荐列表失败:', error);
      return { recommendations: [], message: '加载失败' };
    }
  }
  
  /**
   * 切换点赞状态
   * @param recipeId 配方ID
   */
  public async toggleLike(recipeId: string): Promise<object> {
    try {
      const url = `${this.baseURL}/api/recipes/${recipeId}/like`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.POST);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        return response.result as object;
      } else {
        throw new APIError('点赞操作失败', 'OPERATION_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 点赞操作失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('点赞请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 切换收藏状态
   * @param recipeId 配方ID
   */
  public async toggleFavorite(recipeId: string): Promise<object> {
    try {
      const url = `${this.baseURL}/api/recipes/${recipeId}/favorite`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.POST);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        return response.result as object;
      } else {
        throw new APIError('收藏操作失败', 'OPERATION_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 收藏操作失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('收藏请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 获取评论列表
   * @param recipeId 配方ID
   */
  public async fetchComments(recipeId: string): Promise<Array<object>> {
    try {
      const url = `${this.baseURL}/api/recipes/${recipeId}/comments`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        return response.result as Array<object>;
      } else {
        throw new APIError('获取评论失败', 'FETCH_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 获取评论失败:', error);
      return [];
    }
  }
  
  /**
   * 添加评论
   * @param recipeId 配方ID
   * @param text 评论内容
   * 对应 server.js: POST /api/recipes/:id/comments
   */
  public async addComment(recipeId: string, text: string): Promise<object> {
    try {
      const url = `${this.baseURL}/api/recipes/${recipeId}/comments`;
      const requestBody: CommentRequestBody = {
        commentText: text
      };
      const requestOptions = this.createRequestOptions(
        http.RequestMethod.POST,
        { contentType: 'application/json' },
        requestBody
      );
      const response = await http.createHttp().request(url, requestOptions);
      
      // server.js 返回 201 Created
      if (response.responseCode === 201 || response.responseCode === 200) {
        return response.result as object;
      } else {
        throw new APIError('添加评论失败', 'OPERATION_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 添加评论失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('添加评论请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 获取用户收藏列表
   */
  public async fetchUserFavorites(): Promise<Array<object>> {
    try {
      if (!this._isLoggedIn) {
        throw new APIError('请先登录', 'NOT_LOGGED_IN');
      }
      
      const url = `${this.baseURL}/api/user/favorites`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        const result = response.result;
        
        // 策略1: 直接返回数组 (服务器直接返回数组的情况)
        if (Array.isArray(result)) {
          console.info('[APIService] fetchUserFavorites: 直接数组格式, count=' + result.length);
          return result;
        }
        
        // 策略2: APIResponse 包装格式 { data: [...] }
        const wrapped = result as APIResponse<Array<object>>;
        if (wrapped && Array.isArray(wrapped.data)) {
          console.info('[APIService] fetchUserFavorites: APIResponse包装格式, count=' + wrapped.data.length);
          return wrapped.data;
        }
        
        console.warn('[APIService] fetchUserFavorites: 未知响应格式', result);
        return [];
      } else {
        throw new APIError('获取收藏失败', 'FETCH_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 获取收藏失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('获取收藏请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 获取用户创建的配方列表
   */
  public async fetchUserCreatedRecipes(): Promise<Array<object>> {
    try {
      if (!this._isLoggedIn) {
        throw new APIError('请先登录', 'NOT_LOGGED_IN');
      }
      
      const url = `${this.baseURL}/api/user/created-recipes`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        const result = response.result;
        
        // 策略1: 直接返回数组 (服务器直接返回数组的情况)
        if (Array.isArray(result)) {
          console.info('[APIService] fetchUserCreatedRecipes: 直接数组格式, count=' + result.length);
          return result;
        }
        
        // 策略2: APIResponse 包装格式 { data: [...] }
        const wrapped = result as APIResponse<Array<object>>;
        if (wrapped && Array.isArray(wrapped.data)) {
          console.info('[APIService] fetchUserCreatedRecipes: APIResponse包装格式, count=' + wrapped.data.length);
          return wrapped.data;
        }
        
        console.warn('[APIService] fetchUserCreatedRecipes: 未知响应格式', result);
        return [];
      } else {
        throw new APIError('获取配方失败', 'FETCH_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 获取配方失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('获取配方请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 获取用户点赞列表
   */
  public async fetchUserLikes(): Promise<Array<object>> {
    try {
      if (!this._isLoggedIn) {
        throw new APIError('请先登录', 'NOT_LOGGED_IN');
      }
      
      const url = `${this.baseURL}/api/user/likes`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      const response = await http.createHttp().request(url, requestOptions);
      
      if (response.responseCode === 200) {
        const result = response.result;
        
        // 策略1: 直接返回数组
        if (Array.isArray(result)) {
          console.info('[APIService] fetchUserLikes: 直接数组格式, count=' + result.length);
          return result;
        }
        
        // 策略2: APIResponse 包装格式
        const wrapped = result as APIResponse<Array<object>>;
        if (wrapped && Array.isArray(wrapped.data)) {
          console.info('[APIService] fetchUserLikes: APIResponse包装格式, count=' + wrapped.data.length);
          return wrapped.data;
        }
        
        console.warn('[APIService] fetchUserLikes: 未知响应格式', result);
        return [];
      } else {
        throw new APIError('获取点赞失败', 'FETCH_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 获取点赞失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('获取点赞请求失败', 'NETWORK_ERROR');
    }
  }
  
  /**
   * 获取随机配方列表(用于推荐)
   * @param limit 数量限制
   */
  public async fetchRandomRecipes(limit: number = 100): Promise<Array<object>> {
    try {
      console.info(`[APIService] 获取随机配方, limit=${limit}`);
      // 使用sort=random获取随机排序的配方
      const response = await this.fetchRecipes(1, limit, '', 'random');
      
      // 类型安全的访问recipes属性
      const responseObj = response as RecipesResponse;
      if (responseObj && responseObj.recipes) {
        const recipes: Array<object> = responseObj.recipes;
        console.info(`[APIService] 获取到 ${recipes.length} 个随机配方`);
        return recipes;
      }
      
      console.warn('[APIService] fetchRandomRecipes: 响应格式异常');
      return [];
    } catch (error) {
      console.error('[APIService] 获取随机配方失败:', error);
      if (error instanceof Error) {
        throw error;
      }
      throw new APIError('获取随机配方失败', 'NETWORK_ERROR');
    }
  }
  
  // TODO: 添加更多API方法
  // - 创建配方
  // - 删除配方
  // - AI生成配方
  // - 管理员相关接口
  
  /**
   * 获取自定义配方的原料列表
   */
  public async fetchCustomIngredients(): Promise<object> {
    const httpRequest = http.createHttp();
    try {
      const url = `${this.baseURL}/api/custom/ingredients`;
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      const response = await httpRequest.request(url, requestOptions);
      
      if (response.responseCode === 200) {
        return response.result as object;
      } else {
        throw new APIError(`获取原料列表失败 (${response.responseCode})`, 'FETCH_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 获取原料列表失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('获取原料列表失败', 'NETWORK_ERROR');
    } finally {
      httpRequest.destroy();
    }
  }
  
  /**
   * 创建新配方
   */
  public async createRecipe(recipeData: object): Promise<object> {
    if (!this.isLoggedIn) {
      throw new APIError('请先登录', 'AUTH_REQUIRED');
    }
    
    const httpRequest = http.createHttp();
    try {
      const url = `${this.baseURL}/api/recipes`;
      const requestOptions = this.createRequestOptions(
        http.RequestMethod.POST,
        undefined,
        recipeData
      );
      const response = await httpRequest.request(url, requestOptions);
      
      if (response.responseCode === 201 || response.responseCode === 200) {
        console.info('[APIService] 创建配方成功');
        return response.result as object;
      } else {
        throw new APIError(`创建配方失败 (${response.responseCode})`, 'CREATE_FAILED');
      }
    } catch (error) {
      console.error('[APIService] 创建配方失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('创建配方失败', 'NETWORK_ERROR');
    } finally {
      httpRequest.destroy();
    }
  }
  
  /**
   * AI智能调酒师 - 根据口味描述生成配方
   * @param tasteDescription 口味描述
   * @param occasion 适用场合（可选）
   * @param alcoholStrength 酒精强度（可选）
   */
  public async generateAIRecipe(
    tasteDescription: string,
    occasion?: string,
    alcoholStrength?: string
  ): Promise<AIGeneratedRecipe> {
    const httpRequest = http.createHttp();
    try {
      const url = `${this.baseURL}/api/custom/generate-recipe`;
      
      const requestBody: AIRecipeRequest = {
        tasteDescription: tasteDescription
      };
      if (occasion && occasion.length > 0) {
        requestBody.occasion = occasion;
      }
      if (alcoholStrength && alcoholStrength.length > 0) {
        requestBody.alcoholStrength = alcoholStrength;
      }
      
      const requestOptions = this.createRequestOptions(
        http.RequestMethod.POST,
        { contentType: 'application/json' },
        requestBody
      );
      
      // 设置较长的超时时间，因为AI生成需要时间
      requestOptions.connectTimeout = 30000;
      requestOptions.readTimeout = 60000;
      
      console.info('[APIService] 正在调用AI生成配方...');
      const response = await httpRequest.request(url, requestOptions);
      
      if (response.responseCode === 200) {
        const result = response.result as object;
        console.info('[APIService] AI配方生成成功, result:', JSON.stringify(result));
        
        // 服务端返回格式: { success: true, recipe: {...}, generatedAt: ... }
        const recipeData = Reflect.get(result, 'recipe') as AIGeneratedRecipe;
        if (recipeData) {
          return recipeData;
        }
        
        // 兼容直接返回配方的情况
        if (Reflect.has(result, 'name') && Reflect.has(result, 'ingredients')) {
          return result as AIGeneratedRecipe;
        }
        
        throw new APIError('AI返回数据格式错误', 'PARSE_ERROR');
      } else {
        const errorResult = response.result as object;
        const message = Reflect.get(errorResult, 'message') as string;
        throw new APIError(message || 'AI生成配方失败', 'AI_GENERATE_FAILED');
      }
    } catch (error) {
      console.error('[APIService] AI生成配方失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('AI生成配方请求失败，请稍后重试', 'NETWORK_ERROR');
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 获取配方评分信息
   */
  async fetchRecipeRatings(recipeId: string): Promise<RecipeRatingResponse> {
    const httpRequest = http.createHttp();
    const url = `${this.baseURL}/api/recipes/${recipeId}/ratings`;
    
    try {
      const requestOptions = this.createRequestOptions(http.RequestMethod.GET);
      console.info(`[APIService] 获取AI分析数据, URL: ${url}`);
      const response = await httpRequest.request(url, requestOptions);
      
      if (response.responseCode === 200) {
        let result: object;
        if (typeof response.result === 'string') {
          result = JSON.parse(response.result) as object;
        } else {
          result = response.result as object;
        }
        
        const aiAnalysis = Reflect.get(result, 'aiAnalysis') as string | undefined;
        console.info(`[APIService] AI分析数据: ${aiAnalysis ? '已找到' : '无数据'}`);
        
        return {
          success: true,
          hasRating: Reflect.get(result, 'hasRating') as boolean,
          ratings: Reflect.get(result, 'ratings') as RecipeScores | undefined,
          calculatedScore: Reflect.get(result, 'calculatedScore') as number | undefined,
          aiAnalysis: aiAnalysis,
          ratedAt: Reflect.get(result, 'ratedAt') as string | undefined
        };
      }
      throw new APIError('获取评分失败', 'FETCH_RATINGS_FAILED');
    } catch (error) {
      console.error('[APIService] 获取评分失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('获取评分请求失败', 'NETWORK_ERROR');
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 保存配方评分
   */
  async saveRecipeRatings(recipeId: string, scores: RecipeScores, aiAnalysis?: string): Promise<object> {
    const httpRequest = http.createHttp();
    const url = `${this.baseURL}/api/recipes/${recipeId}/ratings`;
    
    try {
      const requestBody: SaveRatingsRequest = { scores: scores, aiAnalysis: aiAnalysis };
      const requestOptions = this.createRequestOptions(
        http.RequestMethod.POST,
        { contentType: 'application/json' },
        requestBody
      );
      const response = await httpRequest.request(url, requestOptions);
      
      if (response.responseCode === 200) {
        return response.result as object;
      }
      const errorResult = response.result as object;
      const message = Reflect.get(errorResult, 'message') as string;
      throw new APIError(message || '保存评分失败', 'SAVE_RATINGS_FAILED');
    } catch (error) {
      console.error('[APIService] 保存评分失败:', error);
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('保存评分请求失败', 'NETWORK_ERROR');
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * AI口味分析
   */
  async analyzeRecipeFlavor(recipeId: string): Promise<AIAnalysisResponse> {
    const httpRequest = http.createHttp();
    const url = `${this.baseURL}/api/recipes/${recipeId}/ai-analyze`;
    
    try {
      const emptyBody: EmptyRequest = {};
      const requestOptions = this.createRequestOptions(
        http.RequestMethod.POST,
        { contentType: 'application/json' },
        emptyBody
      );
      requestOptions.connectTimeout = 30000;
      requestOptions.readTimeout = 60000;
      
      console.info(`[APIService] 正在进行AI口味分析, URL: ${url}`);
      const response = await httpRequest.request(url, requestOptions);
      
      console.info(`[APIService] AI分析响应码: ${response.responseCode}`);
      
      if (response.responseCode === 200) {
        let result: object;
        if (typeof response.result === 'string') {
          result = JSON.parse(response.result) as object;
        } else {
          result = response.result as object;
        }
        return {
          success: true,
          analysis: Reflect.get(result, 'analysis') as string,
          analyzedAt: Reflect.get(result, 'analyzedAt') as string
        };
      }
      
      // 解析错误响应
      let errorMessage = 'AI分析失败';
      try {
        let errorResult: object;
        if (typeof response.result === 'string') {
          errorResult = JSON.parse(response.result) as object;
        } else {
          errorResult = response.result as object;
        }
        const msg = Reflect.get(errorResult, 'message') as string;
        if (msg) {
          errorMessage = msg;
        }
      } catch (parseError) {
        console.error('[APIService] 解析错误响应失败:', parseError);
      }
      console.error(`[APIService] AI分析失败: ${errorMessage}`);
      throw new APIError(errorMessage, 'AI_ANALYZE_FAILED');
    } catch (error) {
      console.error('[APIService] AI分析请求异常:', error);
      if (error instanceof APIError) {
        throw error;
      }
      const errMsg = error instanceof Error ? error.message : 'AI分析服务暂时不可用';
      throw new APIError(errMsg, 'AI_SERVICE_ERROR');
    } finally {
      httpRequest.destroy();
    }
  }
}

// 评分响应接口
export interface RecipeRatingResponse {
  success: boolean;
  hasRating: boolean;
  ratings?: RecipeScores;
  calculatedScore?: number;
  aiAnalysis?: string;
  ratedAt?: string;
}

// 评分数据接口
export interface RecipeScores {
  visual: number;      // 外观 (0-10)
  aroma: number;       // 香气 (0-10)
  taste: number;       // 风味 (0-10)
  mouthfeel: number;   // 口感 (0-10)
  finish: number;      // 余韵 (0-10)
}

// AI分析响应接口
export interface AIAnalysisResponse {
  success: boolean;
  analysis: string;
  analyzedAt: string;
}

// 保存评分请求体接口
interface SaveRatingsRequest {
  scores: RecipeScores;
  aiAnalysis?: string;
}

// 空请求体接口
interface EmptyRequest {
  placeholder?: string;
}

// AI配方请求接口
interface AIRecipeRequest {
  tasteDescription: string;
  occasion?: string;
  alcoholStrength?: string;
}

// AI生成的配方接口
export interface AIGeneratedRecipe {
  name: string;
  description: string;
  ingredients: AIIngredient[];
  steps: string[];
  glassware?: string;
  garnish?: string;
  taste_profile?: TasteProfile;
  tips?: string;
  isDemo?: boolean;
}

// AI配方中的配料接口
export interface AIIngredient {
  name: string;
  volume: number;
  abv: number;
  category?: string;
}

// 口味配置接口
interface TasteProfile {
  sweetness: string;
  sourness: string;
  bitterness: string;
  strength: string;
}

// 导出单例实例
export const apiService = APIService.getInstance();
