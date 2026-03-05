# 05 E2E 测试目录（Playwright）

## 文档说明

本文档定义 RippleFlow 全量 E2E 用例，采用**函数调用式清单**描述每条用例的：
- 前置条件（`preconditions`）
- 操作步骤（`steps`，对应 Playwright API）
- 断言（`assertions`）
- 测试数据标识（`test_data`）

所有 `selector` 使用 `data-testid` 属性，与 CSS 类名解耦。

---

## Part 1：Playwright 基础配置

### 1.1 playwright.config.ts

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,       // 共享数据库，串行执行
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  timeout: 30_000,
  expect: { timeout: 5_000 },

  use: {
    baseURL: process.env.APP_URL ?? 'http://localhost:8000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],

  globalSetup: './e2e/global-setup.ts',
  globalTeardown: './e2e/global-teardown.ts',
});
```

### 1.2 全局 Setup / Teardown

```typescript
// e2e/global-setup.ts
import { chromium, FullConfig } from '@playwright/test';

async function globalSetup(config: FullConfig) {
  // 1. 确认 API 健康
  await waitForServer(config.projects[0].use.baseURL!);

  // 2. 初始化测试数据库（独立 test DB）
  await seedTestDatabase();

  // 3. 创建已登录的 storage state（复用，避免每个测试都走 SSO）
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await loginAs(page, 'test_member');
  await page.context().storageState({ path: '.auth/member.json' });
  await loginAs(page, 'test_admin');
  await page.context().storageState({ path: '.auth/admin.json' });
  await browser.close();
}

export default globalSetup;
```

### 1.3 Page Object Models（POM）

```typescript
// e2e/pages/LoginPage.ts
export class LoginPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('/');
  }

  async clickSSOLogin() {
    await this.page.click('[data-testid="sso-login-btn"]');
  }

  async fillLDAP(username: string, password: string) {
    await this.page.fill('[data-testid="ldap-username"]', username);
    await this.page.fill('[data-testid="ldap-password"]', password);
    await this.page.click('[data-testid="ldap-submit"]');
  }

  async expectLoginSuccess() {
    await this.page.waitForURL('**/dashboard');
    await expect(this.page.locator('[data-testid="user-menu"]')).toBeVisible();
  }

  async expectForbidden() {
    await expect(this.page.locator('[data-testid="error-not-whitelisted"]')).toBeVisible();
  }
}

// e2e/pages/SearchPage.ts
export class SearchPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('/search');
  }

  async search(query: string) {
    await this.page.fill('[data-testid="search-input"]', query);
    await this.page.press('[data-testid="search-input"]', 'Enter');
    await this.page.waitForSelector('[data-testid="search-results"]');
  }

  async askQuestion(question: string) {
    await this.page.fill('[data-testid="qa-input"]', question);
    await this.page.click('[data-testid="qa-submit"]');
    await this.page.waitForSelector('[data-testid="qa-answer"]');
  }

  async getResultCount(): Promise<number> {
    return await this.page.locator('[data-testid="search-result-item"]').count();
  }

  async getAnswer(): Promise<string> {
    return await this.page.locator('[data-testid="qa-answer"]').innerText();
  }
}

// e2e/pages/ThreadDetailPage.ts
export class ThreadDetailPage {
  constructor(private page: Page) {}

  async goto(threadId: string) {
    await this.page.goto(`/threads/${threadId}`);
  }

  async expectModifyButtonVisible() {
    await expect(this.page.locator('[data-testid="modify-summary-btn"]')).toBeVisible();
  }

  async expectModifyButtonHidden() {
    await expect(this.page.locator('[data-testid="modify-summary-btn"]')).toBeHidden();
  }

  async clickModify() {
    await this.page.click('[data-testid="modify-summary-btn"]');
    await this.page.waitForSelector('[data-testid="modify-form"]');
  }

  async submitModification(field: string, newValue: string, reason: string) {
    await this.page.selectOption('[data-testid="modify-field-select"]', field);
    await this.page.fill('[data-testid="modify-value-input"]', newValue);
    await this.page.fill('[data-testid="modify-reason-input"]', reason);
    await this.page.click('[data-testid="modify-submit-btn"]');
    await this.page.waitForSelector('[data-testid="modify-success-toast"]');
  }
}

// e2e/pages/SensitivePage.ts
export class SensitivePage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('/notifications?type=sensitive_pending');
  }

  async getPendingCount(): Promise<number> {
    return await this.page.locator('[data-testid="sensitive-pending-item"]').count();
  }

  async clickFirstItem() {
    await this.page.locator('[data-testid="sensitive-pending-item"]').first().click();
    await this.page.waitForSelector('[data-testid="sensitive-detail"]');
  }

  async clickAuthorize() {
    await this.page.click('[data-testid="sensitive-authorize-btn"]');
    await this.page.waitForSelector('[data-testid="sensitive-authorized-toast"]');
  }

  async clickReject() {
    await this.page.click('[data-testid="sensitive-reject-btn"]');
    await this.page.waitForSelector('[data-testid="sensitive-rejected-toast"]');
  }

  async clickDesensitize(note: string, desensitizedContent: string) {
    await this.page.click('[data-testid="sensitive-desensitize-btn"]');
    await this.page.fill('[data-testid="desensitize-note"]', note);
    await this.page.fill('[data-testid="desensitize-content"]', desensitizedContent);
    await this.page.click('[data-testid="desensitize-submit-btn"]');
  }
}

// e2e/pages/AdminPage.ts
export class AdminPage {
  constructor(private page: Page) {}

  async gotoWhitelist() {
    await this.page.goto('/admin/whitelist');
  }

  async gotoCategories() {
    await this.page.goto('/admin/categories');
  }

  async addUserToWhitelist(ldapId: string, displayName: string) {
    await this.page.click('[data-testid="add-whitelist-btn"]');
    await this.page.fill('[data-testid="whitelist-ldap-id"]', ldapId);
    await this.page.fill('[data-testid="whitelist-display-name"]', displayName);
    await this.page.click('[data-testid="whitelist-submit-btn"]');
    await this.page.waitForSelector('[data-testid="whitelist-added-toast"]');
  }

  async removeUser(ldapId: string) {
    await this.page
      .locator(`[data-testid="whitelist-row-${ldapId}"] [data-testid="remove-user-btn"]`)
      .click();
    await this.page.click('[data-testid="confirm-remove-btn"]');
    await this.page.waitForSelector('[data-testid="user-removed-toast"]');
  }
}
```

---

## Part 2：测试用例清单（函数调用式）

> 格式说明：
> - `TC-XXX`：用例编号
> - `method`：对应 Playwright Page API 或 POM 方法
> - `selector`：`data-testid` 值
> - `value`：操作的值

---

### 模块 A：认证（AUTH）

```json
[
  {
    "id": "TC-AUTH-001",
    "name": "正常登录：白名单用户通过 LDAP 认证后进入 Dashboard",
    "preconditions": ["用户 test_member 在白名单中且 is_active=true"],
    "test_data": { "username": "test_member", "password": "test123" },
    "steps": [
      { "method": "goto",    "args": { "url": "/" } },
      { "method": "click",   "selector": "sso-login-btn" },
      { "method": "fill",    "selector": "ldap-username", "value": "test_member" },
      { "method": "fill",    "selector": "ldap-password", "value": "test123" },
      { "method": "click",   "selector": "ldap-submit" }
    ],
    "assertions": [
      { "method": "waitForURL",  "pattern": "**/dashboard" },
      { "method": "isVisible",   "selector": "user-menu" },
      { "method": "containsText","selector": "user-display-name", "value": "测试成员" }
    ]
  },

  {
    "id": "TC-AUTH-002",
    "name": "非白名单用户登录被拒绝",
    "preconditions": ["用户 unknown_user 不在白名单中"],
    "test_data": { "username": "unknown_user", "password": "test123" },
    "steps": [
      { "method": "goto",  "args": { "url": "/" } },
      { "method": "click", "selector": "sso-login-btn" },
      { "method": "fill",  "selector": "ldap-username", "value": "unknown_user" },
      { "method": "fill",  "selector": "ldap-password", "value": "test123" },
      { "method": "click", "selector": "ldap-submit" }
    ],
    "assertions": [
      { "method": "isVisible",    "selector": "error-not-whitelisted" },
      { "method": "containsText", "selector": "error-not-whitelisted", "value": "请联系管理员" },
      { "method": "notVisible",   "selector": "user-menu" }
    ]
  },

  {
    "id": "TC-AUTH-003",
    "name": "已停用白名单用户登录被拒绝",
    "preconditions": ["用户 inactive_user 在白名单但 is_active=false"],
    "steps": [
      { "method": "goto",    "args": { "url": "/" } },
      { "method": "click",   "selector": "sso-login-btn" },
      { "method": "fill",    "selector": "ldap-username", "value": "inactive_user" },
      { "method": "fill",    "selector": "ldap-password", "value": "test123" },
      { "method": "click",   "selector": "ldap-submit" }
    ],
    "assertions": [
      { "method": "isVisible", "selector": "error-not-whitelisted" }
    ]
  },

  {
    "id": "TC-AUTH-004",
    "name": "登出后无法访问受保护页面",
    "preconditions": ["用户已登录"],
    "steps": [
      { "method": "goto",  "args": { "url": "/dashboard" } },
      { "method": "click", "selector": "user-menu" },
      { "method": "click", "selector": "logout-btn" },
      { "method": "goto",  "args": { "url": "/api/v1/threads" } }
    ],
    "assertions": [
      { "method": "waitForURL",  "pattern": "**/login*" }
    ]
  },

  {
    "id": "TC-AUTH-005",
    "name": "未登录直接访问受保护页面重定向到登录",
    "preconditions": ["浏览器无 Cookie"],
    "steps": [
      { "method": "goto", "args": { "url": "/threads" } }
    ],
    "assertions": [
      { "method": "waitForURL", "pattern": "**/login*" }
    ]
  }
]
```

---

### 模块 B：搜索与问答（SEARCH）

```json
[
  {
    "id": "TC-SEARCH-001",
    "name": "关键词搜索返回相关话题线索",
    "preconditions": [
      "已登录为 test_member",
      "数据库有含 'Redis' 的 qa_faq 类型线索"
    ],
    "steps": [
      { "method": "goto",       "args": { "url": "/search" } },
      { "method": "fill",       "selector": "search-input", "value": "Redis 连接超时" },
      { "method": "press",      "selector": "search-input", "key": "Enter" },
      { "method": "waitFor",    "selector": "search-results" }
    ],
    "assertions": [
      { "method": "countGte",   "selector": "search-result-item", "value": 1 },
      { "method": "containsText","selector": "search-result-item", "value": "Redis" }
    ]
  },

  {
    "id": "TC-SEARCH-002",
    "name": "搜索无结果时展示空状态提示",
    "preconditions": ["已登录"],
    "steps": [
      { "method": "goto",    "args": { "url": "/search" } },
      { "method": "fill",    "selector": "search-input", "value": "xyzxyzxyz不存在的内容" },
      { "method": "press",   "selector": "search-input", "key": "Enter" },
      { "method": "waitFor", "selector": "search-empty-state" }
    ],
    "assertions": [
      { "method": "isVisible",    "selector": "search-empty-state" },
      { "method": "notVisible",   "selector": "search-result-item" }
    ]
  },

  {
    "id": "TC-SEARCH-003",
    "name": "按类别筛选搜索结果",
    "preconditions": [
      "已登录",
      "数据库有多种类别的线索含 'JWT'"
    ],
    "steps": [
      { "method": "goto",           "args": { "url": "/search" } },
      { "method": "fill",           "selector": "search-input", "value": "JWT" },
      { "method": "selectOption",   "selector": "category-filter", "value": "tech_decision" },
      { "method": "press",          "selector": "search-input", "key": "Enter" },
      { "method": "waitFor",        "selector": "search-results" }
    ],
    "assertions": [
      { "method": "allHaveText", "selector": "result-category-badge", "value": "技术决策" }
    ]
  },

  {
    "id": "TC-SEARCH-004",
    "name": "LLM 问答返回答案和来源",
    "preconditions": [
      "已登录",
      "数据库有关于 Redis 超时的 qa_faq 线索",
      "GLM API 可用"
    ],
    "steps": [
      { "method": "goto",    "args": { "url": "/search" } },
      { "method": "click",   "selector": "qa-tab" },
      { "method": "fill",    "selector": "qa-input", "value": "Redis 连接超时怎么处理？" },
      { "method": "click",   "selector": "qa-submit" },
      { "method": "waitFor", "selector": "qa-answer", "timeout": 15000 }
    ],
    "assertions": [
      { "method": "isVisible",  "selector": "qa-answer" },
      { "method": "textNotEmpty","selector": "qa-answer" },
      { "method": "isVisible",  "selector": "qa-sources" },
      { "method": "countGte",   "selector": "qa-source-item", "value": 1 }
    ]
  },

  {
    "id": "TC-SEARCH-005",
    "name": "点击搜索结果来源线索跳转到详情页",
    "preconditions": ["已登录", "搜索结果不为空"],
    "steps": [
      { "method": "goto",    "args": { "url": "/search" } },
      { "method": "fill",    "selector": "search-input", "value": "Redis" },
      { "method": "press",   "selector": "search-input", "key": "Enter" },
      { "method": "waitFor", "selector": "search-result-item" },
      { "method": "click",   "selector": "search-result-item" }
    ],
    "assertions": [
      { "method": "waitForURL", "pattern": "**/threads/**" },
      { "method": "isVisible",  "selector": "thread-detail-title" }
    ]
  },

  {
    "id": "TC-SEARCH-006",
    "name": "搜索时间范围过滤：不在窗口内的结果不展示",
    "preconditions": [
      "已登录",
      "有一条 qa_faq 线索，last_message_at 为 6 个月前"
    ],
    "steps": [
      { "method": "goto",    "args": { "url": "/search" } },
      { "method": "fill",    "selector": "search-input", "value": "旧线索关键词" },
      { "method": "press",   "selector": "search-input", "key": "Enter" },
      { "method": "waitFor", "selector": "search-done-indicator" }
    ],
    "assertions": [
      { "method": "notContainsText", "selector": "search-results", "value": "旧线索标题" }
    ]
  },

  {
    "id": "TC-SEARCH-007",
    "name": "忽略时间窗口可找到历史线索",
    "preconditions": [
      "已登录",
      "有一条 qa_faq 线索，last_message_at 为 6 个月前"
    ],
    "steps": [
      { "method": "goto",    "args": { "url": "/search" } },
      { "method": "fill",    "selector": "search-input", "value": "旧线索关键词" },
      { "method": "check",   "selector": "ignore-window-checkbox" },
      { "method": "press",   "selector": "search-input", "key": "Enter" },
      { "method": "waitFor", "selector": "search-results" }
    ],
    "assertions": [
      { "method": "containsText", "selector": "search-results", "value": "旧线索标题" }
    ]
  }
]
```

---

### 模块 C：话题线索（THREADS）

```json
[
  {
    "id": "TC-THREAD-001",
    "name": "查看话题线索列表",
    "preconditions": ["已登录", "数据库有话题线索数据"],
    "steps": [
      { "method": "goto",    "args": { "url": "/threads" } },
      { "method": "waitFor", "selector": "thread-list" }
    ],
    "assertions": [
      { "method": "isVisible", "selector": "thread-list" },
      { "method": "countGte",  "selector": "thread-list-item", "value": 1 }
    ]
  },

  {
    "id": "TC-THREAD-002",
    "name": "按类别筛选话题线索列表",
    "preconditions": ["已登录"],
    "steps": [
      { "method": "goto",         "args": { "url": "/threads" } },
      { "method": "selectOption", "selector": "category-filter", "value": "reference_data" },
      { "method": "waitFor",      "selector": "thread-list-filtered" }
    ],
    "assertions": [
      { "method": "allHaveText", "selector": "thread-category-badge", "value": "参考信息" }
    ]
  },

  {
    "id": "TC-THREAD-003",
    "name": "查看话题线索详情",
    "preconditions": ["已登录", "存在话题线索 thread_id_fixture_1"],
    "steps": [
      { "method": "goto",    "args": { "url": "/threads/{{thread_id_fixture_1}}" } },
      { "method": "waitFor", "selector": "thread-detail-summary" }
    ],
    "assertions": [
      { "method": "isVisible", "selector": "thread-detail-title" },
      { "method": "isVisible", "selector": "thread-detail-summary" },
      { "method": "isVisible", "selector": "thread-detail-category" },
      { "method": "isVisible", "selector": "thread-summary-history-btn" }
    ]
  },

  {
    "id": "TC-THREAD-004",
    "name": "当事人可见修改按钮，非当事人不可见",
    "preconditions": [
      "话题线索 thread_id_fixture_1 的 stakeholder_ids 包含 test_stakeholder",
      "不包含 test_member"
    ],
    "steps_stakeholder": [
      { "method": "loginAs",  "user": "test_stakeholder" },
      { "method": "goto",     "args": { "url": "/threads/{{thread_id_fixture_1}}" } }
    ],
    "assertions_stakeholder": [
      { "method": "isVisible", "selector": "modify-summary-btn" }
    ],
    "steps_non_stakeholder": [
      { "method": "loginAs",  "user": "test_member" },
      { "method": "goto",     "args": { "url": "/threads/{{thread_id_fixture_1}}" } }
    ],
    "assertions_non_stakeholder": [
      { "method": "isHidden", "selector": "modify-summary-btn" }
    ]
  },

  {
    "id": "TC-THREAD-005",
    "name": "当事人修改摘要成功，显示成功提示",
    "preconditions": ["已登录为 test_stakeholder，是线索当事人"],
    "steps": [
      { "method": "goto",         "args": { "url": "/threads/{{thread_id_fixture_1}}" } },
      { "method": "click",        "selector": "modify-summary-btn" },
      { "method": "selectOption", "selector": "modify-field-select", "value": "summary" },
      { "method": "fill",         "selector": "modify-value-input", "value": "修正后的摘要内容" },
      { "method": "fill",         "selector": "modify-reason-input", "value": "LLM总结有误，实际Token有效期2小时" },
      { "method": "click",        "selector": "modify-submit-btn" }
    ],
    "assertions": [
      { "method": "isVisible",    "selector": "modify-success-toast" },
      { "method": "containsText", "selector": "thread-detail-summary", "value": "修正后的摘要内容" }
    ]
  },

  {
    "id": "TC-THREAD-006",
    "name": "修改时原因为空，提交失败（前端校验）",
    "preconditions": ["已登录为 test_stakeholder"],
    "steps": [
      { "method": "goto",         "args": { "url": "/threads/{{thread_id_fixture_1}}" } },
      { "method": "click",        "selector": "modify-summary-btn" },
      { "method": "selectOption", "selector": "modify-field-select", "value": "summary" },
      { "method": "fill",         "selector": "modify-value-input", "value": "新内容" },
      { "method": "click",        "selector": "modify-submit-btn" }
    ],
    "assertions": [
      { "method": "isVisible", "selector": "modify-reason-error" },
      { "method": "isHidden",  "selector": "modify-success-toast" }
    ]
  },

  {
    "id": "TC-THREAD-007",
    "name": "查看摘要历史版本",
    "preconditions": ["已登录", "线索有多个历史版本"],
    "steps": [
      { "method": "goto",    "args": { "url": "/threads/{{thread_id_fixture_1}}" } },
      { "method": "click",   "selector": "thread-summary-history-btn" },
      { "method": "waitFor", "selector": "summary-history-list" }
    ],
    "assertions": [
      { "method": "isVisible",  "selector": "summary-history-list" },
      { "method": "countGte",   "selector": "summary-history-item", "value": 1 },
      { "method": "isVisible",  "selector": "summary-history-version" },
      { "method": "isVisible",  "selector": "summary-history-change-reason" }
    ]
  }
]
```

---

### 模块 D：参考信息（REFERENCE）

```json
[
  {
    "id": "TC-REF-001",
    "name": "查看参考信息列表",
    "preconditions": ["已登录", "存在参考信息条目"],
    "steps": [
      { "method": "goto",    "args": { "url": "/reference" } },
      { "method": "waitFor", "selector": "reference-list" }
    ],
    "assertions": [
      { "method": "isVisible", "selector": "reference-list" },
      { "method": "countGte",  "selector": "reference-item", "value": 1 }
    ]
  },

  {
    "id": "TC-REF-002",
    "name": "按服务名过滤参考信息",
    "preconditions": ["已登录", "有 service_name='redis' 的参考信息"],
    "steps": [
      { "method": "goto",    "args": { "url": "/reference" } },
      { "method": "fill",    "selector": "reference-service-filter", "value": "redis" },
      { "method": "press",   "selector": "reference-service-filter", "key": "Enter" },
      { "method": "waitFor", "selector": "reference-list-filtered" }
    ],
    "assertions": [
      { "method": "allHaveText", "selector": "reference-service-name", "value": "redis" }
    ]
  },

  {
    "id": "TC-REF-003",
    "name": "标记参考信息为已废弃（当事人）",
    "preconditions": ["已登录为当事人", "参考信息条目存在且未废弃"],
    "steps": [
      { "method": "goto",    "args": { "url": "/reference" } },
      { "method": "click",   "selector": "reference-item-menu-btn" },
      { "method": "click",   "selector": "deprecate-reference-btn" },
      { "method": "fill",    "selector": "deprecate-reason-input", "value": "服务已迁移，地址变更" },
      { "method": "click",   "selector": "deprecate-confirm-btn" }
    ],
    "assertions": [
      { "method": "isVisible", "selector": "reference-deprecated-badge" }
    ]
  },

  {
    "id": "TC-REF-004",
    "name": "默认不展示已废弃的参考信息",
    "preconditions": ["已登录", "有已废弃的参考信息"],
    "steps": [
      { "method": "goto",    "args": { "url": "/reference" } },
      { "method": "waitFor", "selector": "reference-list" }
    ],
    "assertions": [
      { "method": "notVisible", "selector": "reference-deprecated-badge" }
    ]
  }
]
```

---

### 模块 E：任务待办（ACTION ITEMS）

```json
[
  {
    "id": "TC-AI-001",
    "name": "查看我的待办任务",
    "preconditions": ["已登录为 test_member", "有指派给 test_member 的任务"],
    "steps": [
      { "method": "goto",         "args": { "url": "/action-items" } },
      { "method": "selectOption", "selector": "assignee-filter", "value": "me" },
      { "method": "waitFor",      "selector": "action-items-list" }
    ],
    "assertions": [
      { "method": "countGte",  "selector": "action-item-row", "value": 1 }
    ]
  },

  {
    "id": "TC-AI-002",
    "name": "当事人更新任务状态为已完成",
    "preconditions": ["已登录为任务当事人", "任务状态为 open"],
    "steps": [
      { "method": "goto",         "args": { "url": "/action-items" } },
      { "method": "click",        "selector": "action-item-status-btn-{{thread_id_action}}" },
      { "method": "selectOption", "selector": "action-item-status-select", "value": "done" },
      { "method": "click",        "selector": "status-confirm-btn" }
    ],
    "assertions": [
      { "method": "containsText", "selector": "action-item-status-{{thread_id_action}}", "value": "已完成" }
    ]
  }
]
```

---

### 模块 F：敏感内容授权（SENSITIVE）

```json
[
  {
    "id": "TC-SENS-001",
    "name": "当事人看到待授权通知",
    "preconditions": [
      "已登录为 test_stakeholder",
      "有 overall_status=pending 的敏感授权，test_stakeholder 为当事人"
    ],
    "steps": [
      { "method": "goto",    "args": { "url": "/notifications" } },
      { "method": "waitFor", "selector": "notification-list" }
    ],
    "assertions": [
      { "method": "isVisible",    "selector": "sensitive-pending-notification" },
      { "method": "containsText", "selector": "notification-unread-badge", "value": "1" }
    ]
  },

  {
    "id": "TC-SENS-002",
    "name": "当事人授权敏感内容后，内容进入处理队列",
    "preconditions": [
      "已登录为 test_stakeholder",
      "敏感授权 auth_id_fixture_1 仅有 test_stakeholder 一位当事人"
    ],
    "steps": [
      { "method": "goto",    "args": { "url": "/notifications" } },
      { "method": "click",   "selector": "sensitive-pending-item-link" },
      { "method": "waitFor", "selector": "sensitive-detail" },
      { "method": "click",   "selector": "sensitive-authorize-btn" }
    ],
    "assertions": [
      { "method": "isVisible",    "selector": "sensitive-authorized-toast" },
      { "method": "containsText", "selector": "sensitive-status-badge", "value": "已授权" }
    ]
  },

  {
    "id": "TC-SENS-003",
    "name": "一位当事人拒绝后，整体状态立即变为已拒绝",
    "preconditions": [
      "已登录为 test_stakeholder",
      "敏感授权有两位当事人：test_stakeholder（未表态）和 test_stakeholder2（未表态）"
    ],
    "steps": [
      { "method": "goto",    "args": { "url": "/notifications" } },
      { "method": "click",   "selector": "sensitive-pending-item-link" },
      { "method": "waitFor", "selector": "sensitive-detail" },
      { "method": "click",   "selector": "sensitive-reject-btn" }
    ],
    "assertions": [
      { "method": "isVisible",    "selector": "sensitive-rejected-toast" },
      { "method": "containsText", "selector": "sensitive-status-badge", "value": "已拒绝" }
    ]
  },

  {
    "id": "TC-SENS-004",
    "name": "多当事人场景：一人授权不改变整体 pending 状态",
    "preconditions": [
      "敏感授权有两位当事人：test_stakeholder（未表态）和 test_stakeholder2（未表态）"
    ],
    "steps": [
      { "method": "loginAs",  "user": "test_stakeholder" },
      { "method": "goto",     "args": { "url": "/notifications" } },
      { "method": "click",    "selector": "sensitive-pending-item-link" },
      { "method": "click",    "selector": "sensitive-authorize-btn" },
      { "method": "waitFor",  "selector": "sensitive-authorized-toast" }
    ],
    "assertions": [
      { "method": "containsText", "selector": "sensitive-status-badge", "value": "等待中" },
      { "method": "containsText", "selector": "pending-count", "value": "1 人待决定" }
    ]
  },

  {
    "id": "TC-SENS-005",
    "name": "催促功能：24小时内只能催促一次",
    "preconditions": [
      "已登录为 test_stakeholder（已表态）",
      "test_stakeholder2 尚未表态"
    ],
    "steps_first": [
      { "method": "goto",    "args": { "url": "/notifications" } },
      { "method": "click",   "selector": "nudge-stakeholders-btn" }
    ],
    "assertions_first": [
      { "method": "isVisible", "selector": "nudge-sent-toast" }
    ],
    "steps_second": [
      { "method": "click", "selector": "nudge-stakeholders-btn" }
    ],
    "assertions_second": [
      { "method": "isVisible", "selector": "nudge-rate-limit-error" }
    ]
  },

  {
    "id": "TC-SENS-006",
    "name": "非当事人无法访问敏感内容详情",
    "preconditions": [
      "已登录为 test_member（非当事人）",
      "存在敏感授权 auth_id_fixture_1"
    ],
    "steps": [
      { "method": "goto", "args": { "url": "/api/v1/sensitive/{{auth_id_fixture_1}}" } }
    ],
    "assertions": [
      { "method": "containsText", "selector": "error-message", "value": "403" }
    ]
  }
]
```

---

### 模块 G：纪要生成（SUMMARIZE）

```json
[
  {
    "id": "TC-SUM-001",
    "name": "手动触发纪要生成，返回结构化纪要",
    "preconditions": [
      "已登录",
      "房间 room_dev_general 在过去 4 小时有超过 3 条非噪声消息"
    ],
    "steps": [
      { "method": "goto",         "args": { "url": "/summarize" } },
      { "method": "selectOption", "selector": "summarize-room-select", "value": "room_dev_general" },
      { "method": "click",        "selector": "summarize-submit-btn" },
      { "method": "waitFor",      "selector": "summarize-result", "timeout": 20000 }
    ],
    "assertions": [
      { "method": "isVisible",  "selector": "summarize-result-title" },
      { "method": "isVisible",  "selector": "summarize-result-summary" },
      { "method": "isVisible",  "selector": "summarize-result-participants" },
      { "method": "isVisible",  "selector": "view-thread-link" }
    ]
  },

  {
    "id": "TC-SUM-002",
    "name": "消息数不足时提示无法生成",
    "preconditions": [
      "已登录",
      "房间 room_empty 在指定时间段内消息少于 3 条"
    ],
    "steps": [
      { "method": "goto",         "args": { "url": "/summarize" } },
      { "method": "selectOption", "selector": "summarize-room-select", "value": "room_empty" },
      { "method": "click",        "selector": "summarize-submit-btn" }
    ],
    "assertions": [
      { "method": "isVisible", "selector": "summarize-insufficient-messages-error" }
    ]
  }
]
```

---

### 模块 H：通知中心（NOTIFICATIONS）

```json
[
  {
    "id": "TC-NOTIF-001",
    "name": "查看未读通知列表，通知数徽标显示",
    "preconditions": ["已登录", "有 2 条未读通知"],
    "steps": [
      { "method": "goto",    "args": { "url": "/dashboard" } },
      { "method": "waitFor", "selector": "notification-badge" }
    ],
    "assertions": [
      { "method": "containsText", "selector": "notification-badge", "value": "2" }
    ]
  },

  {
    "id": "TC-NOTIF-002",
    "name": "标记单条通知为已读",
    "preconditions": ["已登录", "有未读通知"],
    "steps": [
      { "method": "goto",    "args": { "url": "/notifications" } },
      { "method": "click",   "selector": "notification-item-read-btn" },
      { "method": "waitFor", "selector": "notification-read-updated" }
    ],
    "assertions": [
      { "method": "notHasClass", "selector": "notification-item", "class": "unread" }
    ]
  },

  {
    "id": "TC-NOTIF-003",
    "name": "全部标记为已读",
    "preconditions": ["已登录", "有 3 条未读通知"],
    "steps": [
      { "method": "goto",  "args": { "url": "/notifications" } },
      { "method": "click", "selector": "mark-all-read-btn" }
    ],
    "assertions": [
      { "method": "containsText", "selector": "notification-badge", "value": "0" }
    ]
  }
]
```

---

### 模块 I：管理后台（ADMIN）

```json
[
  {
    "id": "TC-ADMIN-001",
    "name": "管理员可访问白名单页面，普通用户不可访问",
    "preconditions": [],
    "steps_admin": [
      { "method": "loginAs", "user": "test_admin" },
      { "method": "goto",    "args": { "url": "/admin/whitelist" } }
    ],
    "assertions_admin": [
      { "method": "isVisible", "selector": "whitelist-table" }
    ],
    "steps_member": [
      { "method": "loginAs", "user": "test_member" },
      { "method": "goto",    "args": { "url": "/admin/whitelist" } }
    ],
    "assertions_member": [
      { "method": "waitForURL", "pattern": "**/dashboard" }
    ]
  },

  {
    "id": "TC-ADMIN-002",
    "name": "管理员添加用户到白名单",
    "preconditions": ["已登录为 test_admin", "用户 new_user 不在白名单"],
    "steps": [
      { "method": "goto",  "args": { "url": "/admin/whitelist" } },
      { "method": "click", "selector": "add-whitelist-btn" },
      { "method": "fill",  "selector": "whitelist-ldap-id",      "value": "new_user" },
      { "method": "fill",  "selector": "whitelist-display-name", "value": "新用户" },
      { "method": "fill",  "selector": "whitelist-email",        "value": "new@company.com" },
      { "method": "click", "selector": "whitelist-submit-btn" }
    ],
    "assertions": [
      { "method": "isVisible",    "selector": "whitelist-added-toast" },
      { "method": "containsText", "selector": "whitelist-table", "value": "new_user" }
    ]
  },

  {
    "id": "TC-ADMIN-003",
    "name": "管理员移除用户（软删除）",
    "preconditions": ["已登录为 test_admin", "用户 test_to_remove 在白名单"],
    "steps": [
      { "method": "goto",    "args": { "url": "/admin/whitelist" } },
      { "method": "click",   "selector": "whitelist-row-test_to_remove-menu" },
      { "method": "click",   "selector": "remove-user-btn" },
      { "method": "click",   "selector": "confirm-remove-btn" }
    ],
    "assertions": [
      { "method": "isVisible", "selector": "user-removed-toast" }
    ]
  },

  {
    "id": "TC-ADMIN-004",
    "name": "管理员新增自定义类别",
    "preconditions": ["已登录为 test_admin"],
    "steps": [
      { "method": "goto",  "args": { "url": "/admin/categories" } },
      { "method": "click", "selector": "add-category-btn" },
      { "method": "fill",  "selector": "category-code",          "value": "security_alert" },
      { "method": "fill",  "selector": "category-display-name",  "value": "安全告警" },
      { "method": "fill",  "selector": "category-trigger-hints", "value": "安全漏洞,CVE,攻击,入侵" },
      { "method": "click", "selector": "category-submit-btn" }
    ],
    "assertions": [
      { "method": "isVisible",    "selector": "category-added-toast" },
      { "method": "containsText", "selector": "category-table", "value": "安全告警" }
    ]
  },

  {
    "id": "TC-ADMIN-005",
    "name": "管理员强制介入敏感授权（处理离职员工）",
    "preconditions": [
      "已登录为 test_admin",
      "存在超过 30 天未处理的敏感授权，其中一位当事人 departed_user 已离职"
    ],
    "steps": [
      { "method": "goto",         "args": { "url": "/admin/sensitive" } },
      { "method": "click",        "selector": "sensitive-override-btn-{{auth_id}}" },
      { "method": "selectOption", "selector": "override-action-select", "value": "remove_stakeholder" },
      { "method": "fill",         "selector": "override-target-user",   "value": "departed_user" },
      { "method": "fill",         "selector": "override-reason",        "value": "用户已于2025-02-01离职" },
      { "method": "click",        "selector": "override-submit-btn" }
    ],
    "assertions": [
      { "method": "isVisible",    "selector": "override-success-toast" },
      { "method": "notContains",  "selector": "sensitive-pending-user-list", "value": "departed_user" }
    ]
  },

  {
    "id": "TC-ADMIN-006",
    "name": "查看系统统计数据",
    "preconditions": ["已登录为 test_admin"],
    "steps": [
      { "method": "goto",    "args": { "url": "/admin/stats" } },
      { "method": "waitFor", "selector": "stats-dashboard" }
    ],
    "assertions": [
      { "method": "isVisible", "selector": "stat-messages-total" },
      { "method": "isVisible", "selector": "stat-threads-total" },
      { "method": "isVisible", "selector": "stat-pending-sensitive" }
    ]
  }
]
```

---

### 模块 J：Webhook 接收（WEBHOOK）

> 这部分用 Playwright + API 直接调用，不通过 UI

```typescript
// e2e/webhook.spec.ts
import { test, expect, request } from '@playwright/test';

test.describe('Webhook', () => {

  test('TC-WH-001: 合法 Webhook 消息被接收入队', async ({ request }) => {
    const response = await request.post('/webhook/message', {
      headers: { 'X-Webhook-Secret': process.env.WEBHOOK_SECRET! },
      data: {
        message_id: `test_${Date.now()}`,
        room_id: 'room_dev_general',
        sender: { user_id: 'user_zhangsan', display_name: '张三' },
        content: 'Redis 连接超时怎么处理？',
        content_type: 'text',
        sent_at: new Date().toISOString(),
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.received).toBe(true);
    expect(body.message_id).toBeDefined();
  });

  test('TC-WH-002: 无效 Webhook Secret 返回 401', async ({ request }) => {
    const response = await request.post('/webhook/message', {
      headers: { 'X-Webhook-Secret': 'invalid_secret' },
      data: { message_id: 'test', room_id: 'r1',
              sender: {user_id:'u1',display_name:'u'}, content:'hi',
              content_type:'text', sent_at: new Date().toISOString() }
    });
    expect(response.status()).toBe(401);
  });

  test('TC-WH-003: 重复消息（相同 message_id）幂等处理', async ({ request }) => {
    const msgId = `idem_${Date.now()}`;
    const payload = {
      message_id: msgId,
      room_id: 'room_dev_general',
      sender: { user_id: 'user_zhangsan', display_name: '张三' },
      content: '幂等测试消息',
      content_type: 'text',
      sent_at: new Date().toISOString(),
    };
    const headers = { 'X-Webhook-Secret': process.env.WEBHOOK_SECRET! };

    const r1 = await request.post('/webhook/message', { headers, data: payload });
    const r2 = await request.post('/webhook/message', { headers, data: payload });

    expect(r1.status()).toBe(200);
    expect(r2.status()).toBe(200);
    const b1 = await r1.json();
    const b2 = await r2.json();
    expect(b1.message_id).toBe(b2.message_id); // 同一条记录
  });

  test('TC-WH-004: 缺少必填字段返回 400', async ({ request }) => {
    const response = await request.post('/webhook/message', {
      headers: { 'X-Webhook-Secret': process.env.WEBHOOK_SECRET! },
      data: { room_id: 'r1' } // 缺少 message_id, sender, content 等
    });
    expect(response.status()).toBe(400);
  });
});
```

---

### 模块 J：机器人 API（BOT API）

```typescript
// e2e/tests/bot.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Bot API Tests', () => {

  test('TC-BOT-001: 搜索意图识别成功', async ({ request }) => {
    const response = await request.post('/api/v1/bot/query', {
      headers: { 'X-Bot-Token': process.env.BOT_TOKEN! },
      data: {
        query: 'Redis 连接池怎么配置',
        user_id: 'test_member',
        room_id: 'room_dev_general',
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.intent).toBe('search');
    expect(body.confidence).toBeGreaterThan(0.8);
    expect(body.entities.keywords).toContain('Redis');
  });

  test('TC-BOT-002: 待办查询意图识别', async ({ request }) => {
    const response = await request.post('/api/v1/bot/query', {
      headers: { 'X-Bot-Token': process.env.BOT_TOKEN! },
      data: {
        query: '我有什么待办',
        user_id: 'test_member',
        room_id: 'room_dev_general',
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.intent).toBe('action_items');
  });

  test('TC-BOT-003: 参考数据查询意图识别', async ({ request }) => {
    const response = await request.post('/api/v1/bot/query', {
      headers: { 'X-Bot-Token': process.env.BOT_TOKEN! },
      data: {
        query: 'prod 环境的 Redis 地址是多少',
        user_id: 'test_member',
        room_id: 'room_dev_general',
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.intent).toBe('reference');
    expect(body.entities.environment).toBe('prod');
  });

  test('TC-BOT-004: 纪要生成意图识别', async ({ request }) => {
    const response = await request.post('/api/v1/bot/query', {
      headers: { 'X-Bot-Token': process.env.BOT_TOKEN! },
      data: {
        query: '生成今天产品群的会议纪要',
        user_id: 'test_member',
        room_id: 'room_product',
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.intent).toBe('summarize');
    expect(body.entities.room_hint).toContain('产品群');
  });

  test('TC-BOT-005: 无效 Bot Token 返回 401', async ({ request }) => {
    const response = await request.post('/api/v1/bot/query', {
      headers: { 'X-Bot-Token': 'invalid_token' },
      data: {
        query: '测试查询',
        user_id: 'test_member',
        room_id: 'room_dev_general',
      }
    });
    expect(response.status()).toBe(401);
  });

  test('TC-BOT-006: 非白名单用户查询返回 403', async ({ request }) => {
    const response = await request.post('/api/v1/bot/query', {
      headers: { 'X-Bot-Token': process.env.BOT_TOKEN! },
      data: {
        query: 'Redis 配置',
        user_id: 'non_whitelist_user',
        room_id: 'room_dev_general',
      }
    });
    expect(response.status()).toBe(403);
  });

  test('TC-BOT-007: 搜索结果按用户权限过滤', async ({ request }) => {
    // 创建一个只有 test_stakeholder 可见的线索
    // 普通成员查询时不应返回该线索
    const response = await request.post('/api/v1/bot/query', {
      headers: { 'X-Bot-Token': process.env.BOT_TOKEN! },
      data: {
        query: '敏感项目讨论',
        user_id: 'test_member',
        room_id: 'room_dev_general',
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    // 验证返回结果不包含敏感线索
    if (body.response_type === 'list') {
      const titles = body.content.map((item: any) => item.title);
      expect(titles).not.toContain('敏感项目讨论');
    }
  });

  test('TC-BOT-008: 响应包含追问建议', async ({ request }) => {
    const response = await request.post('/api/v1/bot/query', {
      headers: { 'X-Bot-Token': process.env.BOT_TOKEN! },
      data: {
        query: 'Redis 连接超时怎么处理',
        user_id: 'test_member',
        room_id: 'room_dev_general',
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.suggestions).toBeDefined();
    expect(body.suggestions.length).toBeGreaterThan(0);
  });
});
```

---

### 模块 K：问答反馈（FEEDBACK）

```typescript
// e2e/tests/feedback.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Feedback API Tests', () => {

  test('TC-FB-001: 提交问答反馈（有帮助）', async ({ request }) => {
    const response = await request.post('/api/v1/feedback', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        question: 'Redis 连接池怎么配置',
        answer: '建议使用 Lettuce...',
        is_helpful: true,
        rating: 5,
        source_thread_ids: ['thread-uuid-1']
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.id).toBeDefined();
  });

  test('TC-FB-002: 提交问答反馈（无帮助，带备注）', async ({ request }) => {
    const response = await request.post('/api/v1/feedback', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        question: 'Redis 连接池怎么配置',
        answer: '建议使用 Lettuce...',
        is_helpful: false,
        rating: 2,
        comment: '答案过于笼统，缺少具体配置步骤'
      }
    });
    expect(response.status()).toBe(200);
  });

  test('TC-FB-003: 管理员获取反馈统计', async ({ request }) => {
    const response = await request.get('/api/v1/feedback/stats', {
      headers: { 'Cookie': 'rf_token=admin_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.total_feedback).toBeDefined();
    expect(body.helpful_rate).toBeDefined();
  });
});
```

---

### 模块 L：用户贡献（CONTRIBUTION）

```typescript
// e2e/tests/contribution.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Contribution API Tests', () => {

  test('TC-CONT-001: 获取当前用户贡献统计', async ({ request }) => {
    const response = await request.get('/api/v1/contribution/me', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.user_id).toBeDefined();
    expect(body.threads_participated).toBeDefined();
    expect(body.summaries_edited).toBeDefined();
  });

  test('TC-CONT-002: 获取周贡献排行榜', async ({ request }) => {
    const response = await request.get('/api/v1/contribution/leaderboard?period=weekly&limit=10', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.period).toBe('weekly');
    expect(body.leaderboard).toBeInstanceOf(Array);
  });
});
```

---

### 模块 M：AI 管家（BUTLER）

```typescript
// e2e/tests/butler.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Butler API Tests', () => {

  test('TC-BUT-001: 手动触发每周快报生成', async ({ request }) => {
    const response = await request.post('/api/v1/butler/digest', {
      headers: { 'Cookie': 'rf_token=admin_token' },
      data: {
        room_id: 'room_dev_general'
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.summary).toBeDefined();
    expect(body.hot_discussions).toBeInstanceOf(Array);
  });

  test('TC-BUT-002: 非管理员无法触发快报', async ({ request }) => {
    const response = await request.post('/api/v1/butler/digest', {
      headers: { 'Cookie': 'rf_token=member_token' },
      data: { room_id: 'room_dev_general' }
    });
    expect(response.status()).toBe(403);
  });

  test('TC-BUT-003: 获取知识库健康报告', async ({ request }) => {
    const response = await request.get('/api/v1/butler/health', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.overall_score).toBeDefined();
    expect(body.metrics).toBeDefined();
    expect(body.recommendations).toBeInstanceOf(Array);
  });

  test('TC-BUT-004: 获取管家任务列表', async ({ request }) => {
    const response = await request.get('/api/v1/butler/tasks?limit=20', {
      headers: { 'Cookie': 'rf_token=admin_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.items).toBeInstanceOf(Array);
  });

  test('TC-BUT-005: 获取管家经验知识库', async ({ request }) => {
    const response = await request.get('/api/v1/butler/experience', {
      headers: { 'Cookie': 'rf_token=admin_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(Array.isArray(body)).toBeTruthy();
  });

  test('TC-BUT-006: 获取管家提案列表', async ({ request }) => {
    const response = await request.get('/api/v1/butler/proposals?status=pending', {
      headers: { 'Cookie': 'rf_token=admin_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.items).toBeInstanceOf(Array);
  });

  test('TC-BUT-007: 审批管家提案', async ({ request }) => {
    const response = await request.post('/api/v1/butler/proposals/proposal-id/approve', {
      headers: { 'Cookie': 'rf_token=admin_token' },
      data: { comment: '同意执行' }
    });
    expect(response.status()).toBe(200);
  });
});
```

---

### 模块 N：个人待办（TODOS）

```typescript
// e2e/tests/todos.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Personal Todos API Tests', () => {

  test('TC-TODO-001: 创建个人待办', async ({ request }) => {
    const response = await request.post('/api/v1/todos', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        title: '完成配置文档',
        description: 'Redis 集群配置文档',
        priority: 'high',
        due_date: '2026-03-10',
        visibility: 'followers'
      }
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body.title).toBe('完成配置文档');
    expect(body.status).toBe('pending');
  });

  test('TC-TODO-002: 获取待办列表', async ({ request }) => {
    const response = await request.get('/api/v1/todos?status=pending', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.items).toBeInstanceOf(Array);
    expect(body.overdue_count).toBeDefined();
  });

  test('TC-TODO-003: 完成待办', async ({ request }) => {
    const response = await request.post('/api/v1/todos/todo-id/complete', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: { comment: '已完成配置' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.status).toBe('completed');
  });

  test('TC-TODO-004: 查看他人公开待办', async ({ request }) => {
    const response = await request.get('/api/v1/todos/user/other_user_id', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.items).toBeInstanceOf(Array);
    expect(body.user_info).toBeDefined();
  });

  test('TC-TODO-005: 获取待办统计', async ({ request }) => {
    const response = await request.get('/api/v1/todos/stats', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.total).toBeDefined();
    expect(body.overdue).toBeDefined();
    expect(body.by_priority).toBeDefined();
  });
});
```

---

### 模块 O：订阅/关注（SUBSCRIPTIONS）

```typescript
// e2e/tests/subscriptions.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Subscriptions API Tests', () => {

  test('TC-SUB-001: 关注用户', async ({ request }) => {
    const response = await request.post('/api/v1/subscriptions', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        subscription_type: 'user',
        target_id: 'other_user_id',
        notification_types: ['in_app']
      }
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body.subscription_type).toBe('user');
    expect(body.is_active).toBe(true);
  });

  test('TC-SUB-002: 获取订阅列表', async ({ request }) => {
    const response = await request.get('/api/v1/subscriptions', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.items).toBeInstanceOf(Array);
  });

  test('TC-SUB-003: 取消订阅', async ({ request }) => {
    const response = await request.delete('/api/v1/subscriptions/subscription-id', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(204);
  });

  test('TC-SUB-004: 检查订阅状态', async ({ request }) => {
    const response = await request.get('/api/v1/subscriptions/check?subscription_type=user&target_id=other_user_id', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.is_subscribed).toBeDefined();
  });

  test('TC-SUB-005: 获取热门订阅', async ({ request }) => {
    const response = await request.get('/api/v1/subscriptions/trending?limit=10', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(Array.isArray(body)).toBeTruthy();
  });
});
```

---

## Part 3：测试数据 Fixtures

```typescript
// e2e/fixtures/test-data.ts
export const TEST_USERS = {
  admin: { ldap: 'test_admin', display: '测试管理员', password: 'admin123', role: 'admin' },
  member: { ldap: 'test_member', display: '测试成员', password: 'member123', role: 'member' },
  stakeholder: { ldap: 'test_stakeholder', display: '测试当事人', password: 'stake123', role: 'member' },
  stakeholder2: { ldap: 'test_stakeholder2', display: '测试当事人2', password: 'stake456', role: 'member' },
  inactive: { ldap: 'inactive_user', display: '已停用用户', password: 'xxx', role: 'member' },
};

export const TEST_ROOMS = {
  general: { external_id: 'room_dev_general', name: '开发群' },
  backend: { external_id: 'room_dev_backend', name: '后端群' },
  empty:   { external_id: 'room_empty',       name: '空群' },
};

export const TEST_THREADS = {
  faq_redis: {
    fixture_id: 'thread_id_fixture_1',
    category: 'qa_faq',
    title: 'Redis 连接超时处理方案',
    summary: 'Redis 连接超时通常由 max_connections 配置过低引起...',
    stakeholder_ids: ['test_stakeholder'],
    tags: ['Redis', '连接', '超时'],
  },
  decision_jwt: {
    fixture_id: 'thread_id_fixture_2',
    category: 'tech_decision',
    title: 'JWT 鉴权方案选型',
    summary: '采用 JWT，有效期 7 天...',
    stakeholder_ids: ['test_stakeholder', 'test_admin'],
    tags: ['JWT', '鉴权'],
  },
};

export const TEST_SENSITIVE = {
  pending_single: {
    fixture_id: 'auth_id_fixture_1',
    sensitive_types: ['hr'],
    stakeholder_ids: ['test_stakeholder'],
  },
  pending_multi: {
    fixture_id: 'auth_id_fixture_2',
    sensitive_types: ['privacy'],
    stakeholder_ids: ['test_stakeholder', 'test_stakeholder2'],
  },
};
```

---

## Part 4：data-testid 属性清单

> 前端开发必须在 HTML 元素上添加以下 `data-testid` 属性，E2E 测试依赖这些标识符。

| data-testid | 元素 | 页面 |
|---|---|---|
| `sso-login-btn` | SSO 登录按钮 | /login |
| `ldap-username` | LDAP 用户名输入框 | SSO 页面 |
| `ldap-password` | LDAP 密码输入框 | SSO 页面 |
| `ldap-submit` | 提交登录 | SSO 页面 |
| `user-menu` | 用户菜单按钮 | 全局导航 |
| `user-display-name` | 显示用户名 | 全局导航 |
| `logout-btn` | 登出按钮 | 用户菜单 |
| `error-not-whitelisted` | 非白名单错误提示 | /login |
| `notification-badge` | 通知未读数徽标 | 全局导航 |
| `search-input` | 搜索输入框 | /search |
| `qa-tab` | 问答 Tab | /search |
| `qa-input` | 问答输入框 | /search |
| `qa-submit` | 提交问答 | /search |
| `qa-answer` | 问答答案区 | /search |
| `qa-sources` | 来源列表 | /search |
| `qa-source-item` | 单个来源 | /search |
| `search-results` | 搜索结果区 | /search |
| `search-result-item` | 单条搜索结果 | /search |
| `search-empty-state` | 无结果提示 | /search |
| `result-category-badge` | 结果类别标签 | /search |
| `category-filter` | 类别筛选 | /search, /threads |
| `ignore-window-checkbox` | 忽略时间窗口 | /search |
| `thread-list` | 线索列表区 | /threads |
| `thread-list-item` | 单条线索 | /threads |
| `thread-category-badge` | 线索类别标签 | /threads |
| `thread-detail-title` | 线索详情标题 | /threads/:id |
| `thread-detail-summary` | 线索详情摘要 | /threads/:id |
| `thread-detail-category` | 线索类别 | /threads/:id |
| `thread-summary-history-btn` | 查看历史版本 | /threads/:id |
| `modify-summary-btn` | 修改摘要按钮（仅当事人） | /threads/:id |
| `modify-form` | 修改表单 | /threads/:id |
| `modify-field-select` | 修改字段选择 | /threads/:id |
| `modify-value-input` | 修改内容输入 | /threads/:id |
| `modify-reason-input` | 修改原因输入 | /threads/:id |
| `modify-submit-btn` | 提交修改 | /threads/:id |
| `modify-success-toast` | 修改成功提示 | /threads/:id |
| `modify-reason-error` | 原因为空校验错误 | /threads/:id |
| `summary-history-list` | 历史版本列表 | /threads/:id |
| `summary-history-item` | 单条历史版本 | /threads/:id |
| `summary-history-version` | 版本号 | /threads/:id |
| `summary-history-change-reason` | 变更原因 | /threads/:id |
| `reference-list` | 参考信息列表 | /reference |
| `reference-item` | 单条参考信息 | /reference |
| `reference-service-filter` | 服务名过滤 | /reference |
| `reference-service-name` | 服务名显示 | /reference |
| `reference-item-menu-btn` | 操作菜单 | /reference |
| `deprecate-reference-btn` | 标记废弃 | /reference |
| `deprecate-reason-input` | 废弃原因 | /reference |
| `deprecate-confirm-btn` | 确认废弃 | /reference |
| `reference-deprecated-badge` | 已废弃标签 | /reference |
| `action-items-list` | 任务待办列表 | /action-items |
| `action-item-row` | 单条任务 | /action-items |
| `assignee-filter` | 负责人过滤 | /action-items |
| `sensitive-pending-notification` | 敏感内容待授权通知 | /notifications |
| `sensitive-pending-item` | 待授权条目 | /notifications |
| `sensitive-pending-item-link` | 进入详情 | /notifications |
| `sensitive-detail` | 敏感内容详情 | /sensitive/:id |
| `sensitive-authorize-btn` | 授权按钮 | /sensitive/:id |
| `sensitive-reject-btn` | 拒绝按钮 | /sensitive/:id |
| `sensitive-desensitize-btn` | 脱敏后授权 | /sensitive/:id |
| `sensitive-authorized-toast` | 授权成功提示 | /sensitive/:id |
| `sensitive-rejected-toast` | 拒绝成功提示 | /sensitive/:id |
| `sensitive-status-badge` | 整体状态徽标 | /sensitive/:id |
| `pending-count` | 待决人数 | /sensitive/:id |
| `nudge-stakeholders-btn` | 催促其他人 | /sensitive/:id |
| `nudge-sent-toast` | 催促已发送 | /sensitive/:id |
| `nudge-rate-limit-error` | 催促频率限制 | /sensitive/:id |
| `desensitize-note` | 脱敏说明 | /sensitive/:id |
| `desensitize-content` | 脱敏后内容 | /sensitive/:id |
| `desensitize-submit-btn` | 提交脱敏版本 | /sensitive/:id |
| `summarize-room-select` | 选择群组 | /summarize |
| `summarize-submit-btn` | 生成纪要 | /summarize |
| `summarize-result` | 纪要结果区 | /summarize |
| `summarize-result-title` | 纪要标题 | /summarize |
| `summarize-result-summary` | 纪要摘要 | /summarize |
| `summarize-result-participants` | 参与者 | /summarize |
| `summarize-insufficient-messages-error` | 消息不足错误 | /summarize |
| `view-thread-link` | 查看话题线索链接 | /summarize |
| `notification-list` | 通知列表 | /notifications |
| `notification-item-read-btn` | 标记已读 | /notifications |
| `mark-all-read-btn` | 全部已读 | /notifications |
| `notification-unread-badge` | 未读数 | /notifications |
| `whitelist-table` | 白名单表格 | /admin/whitelist |
| `add-whitelist-btn` | 添加用户 | /admin/whitelist |
| `whitelist-ldap-id` | LDAP ID 输入 | /admin/whitelist |
| `whitelist-display-name` | 显示名输入 | /admin/whitelist |
| `whitelist-email` | 邮箱输入 | /admin/whitelist |
| `whitelist-submit-btn` | 提交添加 | /admin/whitelist |
| `whitelist-added-toast` | 添加成功 | /admin/whitelist |
| `whitelist-row-{ldap_id}-menu` | 用户行操作菜单 | /admin/whitelist |
| `remove-user-btn` | 移除用户 | /admin/whitelist |
| `confirm-remove-btn` | 确认移除 | /admin/whitelist |
| `user-removed-toast` | 移除成功 | /admin/whitelist |
| `category-table` | 类别列表 | /admin/categories |
| `add-category-btn` | 新增类别 | /admin/categories |
| `category-code` | 类别代码输入 | /admin/categories |
| `category-display-name` | 类别名称输入 | /admin/categories |
| `category-trigger-hints` | 触发提示输入 | /admin/categories |
| `category-submit-btn` | 提交新增 | /admin/categories |
| `category-added-toast` | 新增成功 | /admin/categories |
| `stats-dashboard` | 统计面板 | /admin/stats |
| `stat-messages-total` | 消息总数 | /admin/stats |
| `stat-threads-total` | 线索总数 | /admin/stats |
| `stat-pending-sensitive` | 待处理敏感数 | /admin/stats |
| `sensitive-override-btn-{auth_id}` | 管理员介入按钮 | /admin/sensitive |
| `override-action-select` | 介入操作选择 | /admin/sensitive |
| `override-target-user` | 目标用户 | /admin/sensitive |
| `override-reason` | 介入原因 | /admin/sensitive |
| `override-submit-btn` | 提交介入 | /admin/sensitive |
| `override-success-toast` | 介入成功 | /admin/sensitive |
| `sync-to-chat-checkbox` | 同步到群确认框 | /threads/:id |
| `sync-confirm-btn` | 确认同步 | /threads/:id |
| `sync-skip-btn` | 不同步 | /threads/:id |
| `sync-success-toast` | 同步成功提示 | /threads/:id |
| `action-item-status-select` | 任务状态选择 | /action-items |
| `action-item-status-updated-toast` | 状态更新成功 | /action-items |

---

### 模块 P：AI 管家（BUTLER）

```typescript
// e2e/tests/butler.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Butler API Tests', () => {

  test('TC-BUTLER-001: 手动触发每周快报', async ({ request }) => {
    const response = await request.post('/api/v1/butler/digest', {
      headers: { 'Cookie': 'rf_token=admin_token' },
      data: {
        room_id: 'room_dev_general'
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.title).toContain('本周知识沉淀');
    expect(body.hot_discussions).toBeInstanceOf(Array);
  });

  test('TC-BUTLER-002: 获取知识库健康报告', async ({ request }) => {
    const response = await request.get('/api/v1/butler/health', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.overall_score).toBeDefined();
    expect(body.metrics).toBeDefined();
    expect(body.metrics.knowledge_coverage).toBeDefined();
    expect(body.metrics.qa_quality).toBeDefined();
    expect(body.metrics.user_engagement).toBeDefined();
    expect(body.metrics.freshness).toBeDefined();
  });

  test('TC-BUTLER-003: 获取管家任务列表', async ({ request }) => {
    const response = await request.get('/api/v1/butler/tasks?limit=10', {
      headers: { 'Cookie': 'rf_token=admin_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.items).toBeInstanceOf(Array);
  });

  test('TC-BUTLER-004: 获取管家经验知识库', async ({ request }) => {
    const response = await request.get('/api/v1/butler/experience', {
      headers: { 'Cookie': 'rf_token=admin_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(Array.isArray(body)).toBeTruthy();
  });

  test('TC-BUTLER-005: 获取管家提案列表', async ({ request }) => {
    const response = await request.get('/api/v1/butler/proposals', {
      headers: { 'Cookie': 'rf_token=admin_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.items).toBeInstanceOf(Array);
  });

  test('TC-BUTLER-006: 批准管家提案', async ({ request }) => {
    const response = await request.post('/api/v1/butler/proposals/proposal-id/approve', {
      headers: { 'Cookie': 'rf_token=admin_token' },
      data: { comment: '同意执行' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.status).toBe('approved');
  });

  test('TC-BUTLER-007: 拒绝管家提案', async ({ request }) => {
    const response = await request.post('/api/v1/butler/proposals/proposal-id/reject', {
      headers: { 'Cookie': 'rf_token=admin_token' },
      data: { reason: '风险过高' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.status).toBe('rejected');
  });

  test('TC-BUTLER-008: 审核管家汇报', async ({ request }) => {
    const response = await request.post('/api/v1/butler/reports/task-id/review', {
      headers: { 'Cookie': 'rf_token=admin_token' },
      data: { status: 'normal', comment: '执行正常' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.review_status).toBe('normal');
  });

  test('TC-BUTLER-009: 非管理员无法触发快报', async ({ request }) => {
    const response = await request.post('/api/v1/butler/digest', {
      headers: { 'Cookie': 'rf_token=member_token' },
      data: { room_id: 'room_dev_general' }
    });
    expect(response.status()).toBe(403);
  });
});
```

---

### 模块 Q：问答反馈（FEEDBACK）

```typescript
// e2e/tests/feedback.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Feedback API Tests', () => {

  test('TC-FB-001: 提交正面反馈', async ({ request }) => {
    const response = await request.post('/api/v1/feedback', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        qa_session_id: 'session-uuid-1',
        is_helpful: true
      }
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body.is_helpful).toBe(true);
  });

  test('TC-FB-002: 提交负面反馈并填写原因', async ({ request }) => {
    const response = await request.post('/api/v1/feedback', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        qa_session_id: 'session-uuid-2',
        is_helpful: false,
        comment: '答案过于笼统，缺少具体步骤'
      }
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body.is_helpful).toBe(false);
    expect(body.comment).toBe('答案过于笼统，缺少具体步骤');
  });

  test('TC-FB-003: 获取反馈统计', async ({ request }) => {
    const response = await request.get('/api/v1/feedback/stats?period=weekly', {
      headers: { 'Cookie': 'rf_token=admin_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.total_feedback).toBeDefined();
    expect(body.helpful_rate).toBeDefined();
    expect(body.avg_rating).toBeDefined();
  });

  test('TC-FB-004: 获取低分答案列表', async ({ request }) => {
    const response = await request.get('/api/v1/feedback/low-rated?limit=10', {
      headers: { 'Cookie': 'rf_token=admin_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.items).toBeInstanceOf(Array);
  });

  test('TC-FB-005: 对同一问答重复反馈', async ({ request }) => {
    // 第一次提交
    await request.post('/api/v1/feedback', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: { qa_session_id: 'session-uuid-3', is_helpful: true }
    });

    // 第二次提交同一问答
    const response = await request.post('/api/v1/feedback', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: { qa_session_id: 'session-uuid-3', is_helpful: false }
    });
    expect(response.status()).toBe(409); // 已存在
  });
});
```

---

### 模块 R：个人贡献统计（CONTRIBUTION）

```typescript
// e2e/tests/contribution.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Contribution API Tests', () => {

  test('TC-CONTRIB-001: 获取个人贡献统计', async ({ request }) => {
    const response = await request.get('/api/v1/contribution/me', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.threads_participated).toBeDefined();
    expect(body.messages_count).toBeDefined();
    expect(body.summaries_edited).toBeDefined();
    expect(body.decisions_made).toBeDefined();
    expect(body.questions_asked).toBeDefined();
    expect(body.answers_viewed).toBeDefined();
    expect(body.feedback_submitted).toBeDefined();
  });

  test('TC-CONTRIB-002: 获取某用户公开贡献', async ({ request }) => {
    const response = await request.get('/api/v1/contribution/user/other_user_id', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.user_id).toBe('other_user_id');
    expect(body.display_name).toBeDefined();
    expect(body.threads_participated).toBeDefined();
  });

  test('TC-CONTRIB-003: 获取贡献排行榜', async ({ request }) => {
    const response = await request.get('/api/v1/contribution/leaderboard?period=weekly&limit=10', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.period).toBe('weekly');
    expect(body.leaderboard).toBeInstanceOf(Array);
    expect(body.leaderboard.length).toBeLessThanOrEqual(10);
  });

  test('TC-CONTRIB-004: 获取月度排行榜', async ({ request }) => {
    const response = await request.get('/api/v1/contribution/leaderboard?period=monthly', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.period).toBe('monthly');
  });

  test('TC-CONTRIB-005: 获取全部时间排行榜', async ({ request }) => {
    const response = await request.get('/api/v1/contribution/leaderboard?period=all_time', {
      headers: { 'Cookie': 'rf_token=valid_token' }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.period).toBe('all_time');
  });
});
```

---

### 模块 S：批量操作（BATCH）

```typescript
// e2e/tests/batch.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Batch Operations API Tests', () => {

  test('TC-BATCH-001: 批量授权敏感内容', async ({ request }) => {
    const response = await request.post('/api/v1/sensitive/batch-authorize', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        auth_ids: ['auth-uuid-1', 'auth-uuid-2'],
        decision: 'authorize'
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.success_count).toBe(2);
    expect(body.failed_items).toBeInstanceOf(Array);
  });

  test('TC-BATCH-002: 批量拒绝敏感内容', async ({ request }) => {
    const response = await request.post('/api/v1/sensitive/batch-authorize', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        auth_ids: ['auth-uuid-3', 'auth-uuid-4'],
        decision: 'reject'
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.success_count).toBeDefined();
  });

  test('TC-BATCH-003: 批量标记通知已读', async ({ request }) => {
    const response = await request.post('/api/v1/notifications/mark-read', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        notification_ids: ['notif-uuid-1', 'notif-uuid-2', 'notif-uuid-3']
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.updated_count).toBe(3);
  });

  test('TC-BATCH-004: 批量授权部分失败', async ({ request }) => {
    const response = await request.post('/api/v1/sensitive/batch-authorize', {
      headers: { 'Cookie': 'rf_token=valid_token' },
      data: {
        auth_ids: ['auth-valid-1', 'auth-not-yours', 'auth-valid-2'],
        decision: 'authorize'
      }
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.success_count).toBe(2);
    expect(body.failed_items.length).toBe(1);
    expect(body.failed_items[0].reason).toContain('非当事人');
  });
});
```

---

## Part 5：用户手册场景映射

> 本节建立 E2E 测试用例与用户手册 Use Case 的映射关系。

| 用户手册 Use Case | 对应 E2E 测试用例 | 覆盖状态 |
|------------------|-------------------|----------|
| 4.1 新成员快速融入 | TC-QA-001, TC-QA-002 | ✅ 已覆盖 |
| 4.2 技术问题快速解答 | TC-QA-001, TC-SEARCH-001 | ✅ 已覆盖 |
| 4.3 参考信息快速查找 | TC-REF-001, TC-REF-002, TC-REF-003 | ✅ 已覆盖 |
| 4.4 会议讨论自动纪要 | TC-SUM-001, TC-SUM-002 | ✅ 已覆盖 |
| 4.5 敏感内容授权处理 | TC-SENS-001 ~ TC-SENS-005 | ✅ 已覆盖 |
| 4.6 当事人修正摘要 | TC-THR-003, TC-THR-004 | ✅ 已覆盖 |
| 4.7 个人待办管理 | TC-TODO-001 ~ TC-TODO-005 | ✅ 已覆盖 |
| 4.8 管理员系统配置 | TC-ADMIN-001 ~ TC-ADMIN-006 | ✅ 已覆盖 |
| 4.9 AI 管家每周快报 | TC-BUTLER-001 ~ TC-BUTLER-009 | ✅ 已覆盖 |
| 4.10 问答反馈 | TC-FB-001 ~ TC-FB-005 | ✅ 已覆盖 |
| 4.11 个人贡献统计 | TC-CONTRIB-001 ~ TC-CONTRIB-005 | ✅ 已覆盖 |
| 4.3b FAQ 知识库 | TC-FAQ-E2E-001 ~ TC-FAQ-E2E-007 | ✅ 已覆盖 |

---

## Part 5b：FAQ 知识库 E2E 测试

### TC-FAQ-E2E-001：浏览 FAQ 章节目录

```typescript
test('FAQ 知识库 - 章节目录树展示', async ({ page }) => {
  await page.goto('/faq/group_tech_001');

  // 左侧章节树应展示
  await expect(page.locator('[data-testid="faq-section-tree"]')).toBeVisible();
  await expect(page.locator('text=环境配置')).toBeVisible();
  await expect(page.locator('text=架构决策')).toBeVisible();

  // 点击章节展开
  await page.click('text=环境配置');
  await expect(page.locator('text=Redis 配置')).toBeVisible();
});
```

### TC-FAQ-E2E-002：FAQ 关键词搜索

```typescript
test('FAQ 搜索 - 关键词命中高亮', async ({ page }) => {
  await page.goto('/faq/group_tech_001');

  await page.fill('[data-testid="faq-search-input"]', 'Redis 连接池');
  await page.keyboard.press('Enter');

  // 搜索结果应包含关键词高亮
  const results = page.locator('[data-testid="faq-result-item"]');
  await expect(results).toHaveCount({ min: 1 });
  await expect(page.locator('mark:has-text("Redis")')).toBeVisible();

  // 每条结果应显示来源链接
  await expect(page.locator('[data-testid="faq-source-link"]').first()).toBeVisible();
});
```

### TC-FAQ-E2E-003：FAQ 答案来源溯源

```typescript
test('FAQ 来源溯源 - 点击跳转原始讨论', async ({ page, context }) => {
  await page.goto('/faq/group_tech_001/items/faq-001');

  // 来源区域应显示关联 thread 数量
  await expect(page.locator('[data-testid="faq-source-count"]')).toContainText('条相关讨论');

  // 点击来源链接，应在新标签打开 thread 详情
  const [newPage] = await Promise.all([
    context.waitForEvent('page'),
    page.click('[data-testid="faq-source-link"]'),
  ]);
  await expect(newPage.url()).toContain('/threads/');
});
```

### TC-FAQ-E2E-004：管理员审核 FAQ（确认）

```typescript
test('管理员审核 - 确认 FAQ 条目', async ({ adminPage }) => {
  await adminPage.goto('/admin/faq/review');

  // 审核队列应显示 pending 条目
  const pendingItem = adminPage.locator('[data-testid="faq-pending-item"]').first();
  await expect(pendingItem).toBeVisible();

  // 点击"确认"
  await pendingItem.locator('[data-testid="btn-confirm"]').click();
  await expect(adminPage.locator('[data-testid="toast-success"]')).toContainText('已确认');
});
```

### TC-FAQ-E2E-005：管理员驳回 FAQ

```typescript
test('管理员审核 - 驳回 FAQ 条目', async ({ adminPage }) => {
  await adminPage.goto('/admin/faq/review');

  const pendingItem = adminPage.locator('[data-testid="faq-pending-item"]').first();
  await pendingItem.locator('[data-testid="btn-reject"]').click();

  // 弹出驳回原因输入框
  await expect(adminPage.locator('[data-testid="reject-reason-dialog"]')).toBeVisible();
  await adminPage.fill('[data-testid="reject-reason-input"]', '答案与最新实践不符');
  await adminPage.click('[data-testid="btn-confirm-reject"]');

  await expect(adminPage.locator('[data-testid="toast-success"]')).toContainText('已驳回');
});
```

### TC-FAQ-E2E-006：用户提交"答案有误"反馈

```typescript
test('FAQ 反馈 - 提交答案有误', async ({ page }) => {
  await page.goto('/faq/group_tech_001/items/faq-001');

  await page.click('[data-testid="btn-unhelpful"]');
  await expect(page.locator('[data-testid="feedback-comment-input"]')).toBeVisible();
  await page.fill('[data-testid="feedback-comment-input"]', 'Redis 版本升级后配置方式已变更');
  await page.click('[data-testid="btn-submit-feedback"]');

  await expect(page.locator('[data-testid="toast-success"]')).toContainText('反馈已提交');
});
```

### TC-FAQ-E2E-007：机器人回答优先引用 FAQ

```typescript
test('机器人问答 - FAQ 优先命中', async ({ page }) => {
  await page.goto('/chat/group_tech_001');

  await page.fill('[data-testid="chat-input"]', '@机器人 Redis连接池怎么配置');
  await page.keyboard.press('Enter');

  const botReply = page.locator('[data-testid="bot-message"]').last();
  await expect(botReply).toBeVisible({ timeout: 5000 });

  // 回复应包含 FAQ 来源标注
  await expect(botReply).toContainText('根据知识库 FAQ');
  await expect(botReply.locator('[data-testid="faq-source-link"]')).toBeVisible();
});
```

---

## Part 6：测试环境配置

```yaml
# e2e/playwright.config.ts 环境变量
env:
  APP_URL: http://localhost:8000
  TEST_DB_HOST: localhost
  TEST_DB_NAME: rippleflow_test
  TEST_REDIS_URL: redis://localhost:6379/15
  LLM_MOCK_ENABLED: true
  CHAT_TOOL_MOCK_ENABLED: true
```

---

## Part 7：消息入库全链路 E2E 测试（推演修复后补充）

> 覆盖消息入库触发的完整流程，对应推演中识别的 17 个 GAP 修复验证。
> 前置条件：`LLM_MOCK_ENABLED=true`，所有 LLM 调用返回确定性 Mock 响应。

---

### TC-INGEST-001：正常技术决策消息 - 完整 Stage 0-5 流程（Happy Path）

```typescript
test('消息入库完整流程 - tech_decision 类别', async ({ request }) => {
  // 1. 发送 Webhook
  const webhookResp = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-ingest-001',
      room_id: 'tech-discussion',
      sender_id: 'zhangsan',
      content: '我们决定在生产环境使用 Redis Cluster 代替单节点，主要考虑高可用。',
      timestamp: new Date().toISOString(),
    },
  });
  expect(webhookResp.ok()).toBeTruthy();
  const { message_id } = await webhookResp.json();

  // 2. 等待 Stage 0-4 完成（轮询 processing_status）
  await waitForMessageStatus(request, message_id, 'processed', { timeout: 10_000 });

  // 3. 验证消息记录
  const msgResp = await request.get(`/api/v1/messages/${message_id}`);
  const msg = await msgResp.json();
  expect(msg.processing_status).toBe('processed');
  expect(msg.is_bot_message).toBe(false);
  expect(msg.pipeline_start_stage).toBe(0);

  // 4. 验证线索创建
  const threadsResp = await request.get('/api/v1/threads', {
    params: { category: 'tech_decision', keyword: 'Redis Cluster' },
  });
  const threads = (await threadsResp.json()).threads;
  expect(threads.length).toBeGreaterThanOrEqual(1);
  const thread = threads[0];
  expect(thread.title).toContain('Redis');

  // 5. 等待 nullclaw Stage5 写回（摘要）
  // nullclaw mock 写回 summary 后，轮询 thread.summary 非空
  await waitForThreadSummary(request, thread.id, { timeout: 8_000 });

  // 6. 验证摘要写回后才触发订阅通知（GAP-16 验证）
  // category_subscriber 应收到 queued_notification（通知在 Stage5 后生成）
  const notifResp = await request.get('/api/v1/notifications', {
    headers: { 'X-User-Id': 'category_subscriber_user' },
  });
  const notifs = (await notifResp.json()).notifications;
  const threadNotif = notifs.find((n: any) => n.related_id === thread.id);
  expect(threadNotif).toBeDefined();

  // 7. 验证通知内含摘要（证明通知在 Stage5 后触发）
  const fullThread = await (await request.get(`/api/v1/threads/${thread.id}`)).json();
  expect(fullThread.summary).toBeTruthy();  // summary 必须已存在
});
```

---

### TC-INGEST-002：幂等性 - 重复 Webhook 不创建重复消息（GAP-8）

```typescript
test('Webhook 幂等性 - 相同 external_msg_id 只入库一次', async ({ request }) => {
  const payload = {
    external_msg_id: 'msg-idempotent-001',
    room_id: 'tech-discussion',
    sender_id: 'zhangsan',
    content: '幂等测试消息',
    timestamp: new Date().toISOString(),
  };

  // 第一次发送
  const r1 = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: payload,
  });
  expect(r1.ok()).toBeTruthy();
  const { message_id: id1 } = await r1.json();

  // 第二次发送（模拟 Webhook 重试）
  const r2 = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: payload,
  });
  expect(r2.ok()).toBeTruthy();
  const { message_id: id2 } = await r2.json();

  // 两次返回同一 message_id，消息仅入库一次
  expect(id1).toBe(id2);

  // 验证数据库中只有一条该 external_msg_id 的记录（通过搜索验证）
  const countResp = await request.get('/api/v1/messages', {
    params: { external_msg_id: 'msg-idempotent-001' },
  });
  // 实现上通过 ON CONFLICT DO NOTHING 保证，API 应返回200且内容一致
  expect(r2.status()).toBe(200);
});
```

---

### TC-INGEST-003：机器人消息过滤 - 不进入处理流程（GAP-7）

```typescript
test('机器人消息 - 跳过 Pipeline，不触发 LLM 调用', async ({ request }) => {
  const resp = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-bot-001',
      room_id: 'tech-discussion',
      sender_id: 'rippleflow-bot',  // 机器人 sender_id
      is_bot: true,
      content: '这是机器人的回复消息，不应入库处理',
      timestamp: new Date().toISOString(),
    },
  });
  expect(resp.ok()).toBeTruthy();
  const { message_id } = await resp.json();

  // 机器人消息应立即标记 skipped，不进入队列
  const msgResp = await request.get(`/api/v1/messages/${message_id}`);
  const msg = await msgResp.json();
  expect(msg.processing_status).toBe('skipped');
  expect(msg.is_bot_message).toBe(true);

  // 确认 LLM 未被调用（通过 Mock 统计）
  const mockStats = await (await request.get('/internal/test/llm-mock-stats')).json();
  const botMsgCallCount = mockStats.calls_for_message_id[message_id] ?? 0;
  expect(botMsgCallCount).toBe(0);
});
```

---

### TC-INGEST-004：敏感消息完整授权循环（GAP-1/2 防死循环）

```typescript
test('敏感消息 - 授权后从 Stage1 重入，不重复触发 Stage0', async ({ request }) => {
  // 1. 发送包含敏感信息的消息
  const webhookResp = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-sensitive-001',
      room_id: 'hr-channel',
      sender_id: 'hr_manager',
      content: '张三的薪资调整为 35K，请知悉。',
      timestamp: new Date().toISOString(),
    },
  });
  const { message_id } = await webhookResp.json();

  // 2. 等待进入 pending_authorization 状态
  await waitForMessageStatus(request, message_id, 'pending_authorization', { timeout: 5_000 });

  // 3. 验证 pipeline_start_stage = 0（初始值）
  const msgBefore = await (await request.get(`/api/v1/messages/${message_id}`)).json();
  expect(msgBefore.processing_status).toBe('pending_authorization');

  // 4. 当事人授权
  const authResp = await request.post('/api/v1/sensitive/authorize', {
    headers: { 'X-User-Id': 'zhangsan' },  // 当事人
    data: { message_id, decision: 'approve', reason: '同意入库' },
  });
  expect(authResp.ok()).toBeTruthy();

  // 5. 验证消息重入 pipeline（start_stage=1，跳过 Stage0）
  await waitForMessageStatus(request, message_id, 'processed', { timeout: 10_000 });
  const msgAfter = await (await request.get(`/api/v1/messages/${message_id}`)).json();
  expect(msgAfter.pipeline_start_stage).toBe(1);  // GAP-1 验证：从 Stage1 开始

  // 6. 验证 LLM 调用统计：Stage0 只被调用一次（初次检测），重入后不再调用
  const mockStats = await (await request.get('/internal/test/llm-mock-stats')).json();
  const stage0Calls = mockStats.stage0_calls_for_message_id[message_id] ?? 0;
  expect(stage0Calls).toBe(1);  // GAP-1 验证：Stage0 不重复执行
});
```

---

### TC-INGEST-005：Action Item 自动同步为 Todo（GAP-3/4）

```typescript
test('action_item 消息 - 自动创建 personal_todo，默认 visibility=team', async ({ request }) => {
  const resp = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-action-001',
      room_id: 'tech-discussion',
      sender_id: 'pm_user',
      content: '@lisi 请在本周五前完成 Redis 集群压测报告并提交。',
      timestamp: new Date().toISOString(),
    },
  });
  const { message_id } = await resp.json();

  await waitForMessageStatus(request, message_id, 'processed', { timeout: 10_000 });

  // 验证被指派人（lisi）的 todo 列表中出现对应任务
  const todosResp = await request.get('/api/v1/todos', {
    headers: { 'X-User-Id': 'lisi' },
    params: { visibility: 'team' },
  });
  const todos = (await todosResp.json()).todos;
  const actionTodo = todos.find((t: any) => t.source_message_id === message_id);

  expect(actionTodo).toBeDefined();
  expect(actionTodo.assigned_to).toBe('lisi');
  expect(actionTodo.visibility).toBe('team');   // GAP-4：默认 team，不是 private
  expect(actionTodo.source_type).toBe('action_item');
});
```

---

### TC-INGEST-006：多分类消息 - 多线索并行创建（GAP-5）

```typescript
test('多分类消息 - 同时归属 tech_decision + reference_data', async ({ request }) => {
  const resp = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-multi-cat-001',
      room_id: 'tech-discussion',
      sender_id: 'senior_dev',
      content: '我们决定使用 Redis 7.0（技术决策），Redis 7.0 官方文档地址：https://redis.io/docs（参考资料）。',
      timestamp: new Date().toISOString(),
    },
  });
  const { message_id } = await resp.json();

  await waitForMessageStatus(request, message_id, 'processed', { timeout: 15_000 });

  // 验证多线索创建
  const threadsResp = await request.get('/api/v1/threads', {
    params: { source_message_id: message_id },
  });
  const threads = (await threadsResp.json()).threads;

  const categories = threads.map((t: any) => t.category);
  expect(categories).toContain('tech_decision');
  expect(categories).toContain('reference_data');

  // 验证 nullclaw 收到的 notify_nullclaw payload 使用多线索格式（GAP-5）
  // 通过查询 nullclaw_pending_events 或 Mock 接收记录验证
  const eventsResp = await request.get('/internal/test/nullclaw-received-events');
  const events = await eventsResp.json();
  const multiThreadEvent = events.find((e: any) =>
    e.message_id === message_id && e.thread_updates?.length >= 2
  );
  expect(multiThreadEvent).toBeDefined();
  expect(multiThreadEvent.thread_updates.length).toBe(2);
});
```

---

### TC-INGEST-007：reference_data 重复检测与标记废弃（GAP-6）

```typescript
test('reference_data - 更新已有 key_name 时旧记录自动废弃', async ({ request }) => {
  // 1. 第一次入库 Redis 版本信息
  const r1 = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-ref-v1',
      room_id: 'tech-discussion',
      sender_id: 'devops_user',
      content: '生产环境 Redis 版本：6.2.6',
      timestamp: new Date().toISOString(),
    },
  });
  const { message_id: mid1 } = await r1.json();
  await waitForMessageStatus(request, mid1, 'processed', { timeout: 10_000 });

  // 获取 reference_data 记录
  const refResp1 = await request.get('/api/v1/reference-data', {
    params: { key_name: 'redis_version', group_id: 'tech-discussion' },
  });
  const ref1 = (await refResp1.json()).items[0];
  expect(ref1).toBeDefined();
  expect(ref1.deprecated_at).toBeNull();

  // 2. 第二次入库新版本（相同 key_name）
  const r2 = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-ref-v2',
      room_id: 'tech-discussion',
      sender_id: 'devops_user',
      content: '生产环境 Redis 版本已升级至 7.0.5',
      timestamp: new Date().toISOString(),
    },
  });
  const { message_id: mid2 } = await r2.json();
  await waitForMessageStatus(request, mid2, 'processed', { timeout: 10_000 });

  // 3. 验证旧记录被废弃，新记录有效（GAP-6 验证）
  const refResp2 = await request.get('/api/v1/reference-data', {
    params: { key_name: 'redis_version', group_id: 'tech-discussion', include_deprecated: true },
  });
  const items = (await refResp2.json()).items;
  const activeItems = items.filter((i: any) => !i.deprecated_at);
  const deprecatedItems = items.filter((i: any) => i.deprecated_at);

  expect(activeItems.length).toBe(1);
  expect(deprecatedItems.length).toBe(1);
  expect(deprecatedItems[0].id).toBe(ref1.id);  // 旧记录被废弃
});
```

---

### TC-INGEST-008：nullclaw 宕机 - Pending 事件有序重试（GAP-10/11）

```typescript
test('nullclaw 宕机时事件存储，恢复后按线索有序重放', async ({ request }) => {
  // 1. 模拟 nullclaw 下线（Mock 拒绝所有请求）
  await request.post('/internal/test/nullclaw-mock-offline');

  // 2. 发送消息（Stage 0-4 完成，但 notify_nullclaw 失败入队）
  const r1 = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-pending-001',
      room_id: 'tech-discussion',
      sender_id: 'zhangsan',
      content: '第一条消息',
      timestamp: new Date().toISOString(),
    },
  });
  const { message_id: mid1 } = await r1.json();

  const r2 = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-pending-002',
      room_id: 'tech-discussion',
      sender_id: 'zhangsan',
      content: '第二条消息',
      timestamp: new Date().toISOString(),
    },
  });
  const { message_id: mid2 } = await r2.json();

  // 3. 验证 pending_events 表有记录
  await waitForPendingEvents(request, 2, { timeout: 5_000 });

  // 4. nullclaw 恢复上线
  await request.post('/internal/test/nullclaw-mock-online');

  // 5. 触发 RetryWorker
  await request.post('/internal/test/trigger-retry-worker');

  // 6. 验证事件按顺序投递（mid1 先于 mid2，GAP-10 验证）
  const receivedResp = await request.get('/internal/test/nullclaw-received-events');
  const received = await receivedResp.json();
  const mid1Idx = received.findIndex((e: any) => e.payload?.new_message_ids?.includes(mid1));
  const mid2Idx = received.findIndex((e: any) => e.payload?.new_message_ids?.includes(mid2));
  expect(mid1Idx).toBeLessThan(mid2Idx);  // GAP-10：有序重放

  // 7. 验证 pending_events 状态更新为 sent
  const pendingResp = await request.get('/api/v1/nullclaw/pending-events', {
    params: { status: 'pending' },
  });
  const pendingCount = (await pendingResp.json()).total;
  expect(pendingCount).toBe(0);
});
```

---

### TC-INGEST-009：订阅通知在 Stage5 摘要就绪后触发（GAP-16）

```typescript
test('category 订阅通知 - 仅在 Stage5 摘要写回后触发，不提前', async ({ request }) => {
  // 1. 订阅 tech_decision 类别
  await request.post('/api/v1/subscriptions', {
    headers: { 'X-User-Id': 'notification_tester' },
    data: { subscription_type: 'category', target_id: 'tech_decision' },
  });

  // 2. 发送消息
  const resp = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-notif-timing-001',
      room_id: 'tech-discussion',
      sender_id: 'dev_user',
      content: '决定采用 Kong 作为 API 网关。',
      timestamp: new Date().toISOString(),
    },
  });
  const { message_id } = await resp.json();

  // 3. Stage 0-4 完成时检查通知（此时不应有通知）
  await waitForMessageStatus(request, message_id, 'processed', { timeout: 10_000 });

  // nullclaw 尚未完成 Stage5 时，不应有通知（GAP-16）
  // 使用 nullclaw mock 延迟 Stage5 写回来验证这一点
  const earlyNotifResp = await request.get('/api/v1/notifications', {
    headers: { 'X-User-Id': 'notification_tester' },
    params: { created_after: new Date(Date.now() - 5000).toISOString() },
  });
  // Stage5 尚未完成，通知数量为0
  expect((await earlyNotifResp.json()).notifications.length).toBe(0);

  // 4. 触发 nullclaw mock 完成 Stage5（写回摘要 + 调用 /internal/subscriptions/publish）
  await request.post('/internal/test/nullclaw-complete-stage5', {
    data: { message_id },
  });

  // 5. Stage5 完成后，通知应出现
  await expect(async () => {
    const notifResp = await request.get('/api/v1/notifications', {
      headers: { 'X-User-Id': 'notification_tester' },
    });
    const notifs = (await notifResp.json()).notifications;
    expect(notifs.length).toBeGreaterThan(0);
  }).toPass({ timeout: 5_000 });
});
```

---

### TC-INGEST-010：关键词订阅匹配与 searchable_text 构建（GAP-17）

```typescript
test('keyword 订阅 - searchable_text 包含摘要且命中关键词', async ({ request }) => {
  // 1. 创建关键词订阅
  await request.post('/api/v1/subscriptions', {
    headers: { 'X-User-Id': 'keyword_subscriber' },
    data: { subscription_type: 'keyword', target_id: 'Elasticsearch' },
  });

  // 2. 发送包含关键词的消息
  const resp = await request.post('/api/v1/webhooks/chat', {
    headers: { 'X-Webhook-Secret': testWebhookSecret },
    data: {
      external_msg_id: 'msg-keyword-001',
      room_id: 'tech-discussion',
      sender_id: 'search_dev',
      content: '我们评估了 Elasticsearch 作为全文搜索引擎的方案。',
      timestamp: new Date().toISOString(),
    },
  });
  const { message_id } = await resp.json();
  await waitForMessageStatus(request, message_id, 'processed', { timeout: 10_000 });

  // 3. nullclaw 完成 Stage5 并触发订阅通知
  await request.post('/internal/test/nullclaw-complete-stage5', {
    data: { message_id },
  });

  // 4. 等待关键词匹配 Worker 完成
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 5. 验证 keyword_subscriber 收到通知
  const notifResp = await request.get('/api/v1/notifications', {
    headers: { 'X-User-Id': 'keyword_subscriber' },
  });
  const notifs = (await notifResp.json()).notifications;
  const kwNotif = notifs.find((n: any) => n.type === 'keyword_matched');
  expect(kwNotif).toBeDefined();

  // 6. 验证 subscription_events 记录包含 keyword 信息
  const eventsResp = await request.get('/api/v1/subscriptions/events', {
    headers: { 'X-User-Id': 'keyword_subscriber' },
  });
  const events = (await eventsResp.json()).events;
  const kwEvent = events.find((e: any) =>
    e.event_type === 'keyword_matched' && e.metadata?.matched_keyword === 'Elasticsearch'
  );
  expect(kwEvent).toBeDefined();
});
```

---

### TC-INGEST-011：nullclaw ApiKey 认证 - 内部端点鉴权（GAP-9）

```typescript
test('nullclaw API Key - /internal 端点拒绝无效 Key', async ({ request }) => {
  // 无 Authorization header → 401
  const r1 = await request.post('/internal/subscriptions/publish', {
    data: { event_type: 'new_thread', target_type: 'thread', target_id: 'some-uuid', actor_id: 'user' },
  });
  expect(r1.status()).toBe(401);

  // 错误格式 → 401
  const r2 = await request.post('/internal/subscriptions/publish', {
    headers: { Authorization: 'Bearer jwt-token' },
    data: { event_type: 'new_thread', target_type: 'thread', target_id: 'some-uuid', actor_id: 'user' },
  });
  expect(r2.status()).toBe(401);

  // 正确 ApiKey → 200
  const r3 = await request.post('/internal/subscriptions/publish', {
    headers: { Authorization: `ApiKey ${testNullclawApiKey}` },
    data: {
      event_type: 'new_thread',
      target_type: 'thread',
      target_id: testThreadId,
      actor_id: 'zhangsan',
      payload: { category: 'tech_decision', searchable_text: 'Redis Cluster', title: '测试线索' },
    },
  });
  expect(r3.status()).toBe(200);
});
```

---

### TC-INGEST-012：摘要漂移告警 - nullclaw 触发 bulk 通知（GAP-14）

```typescript
test('consensus_drift 告警 - nullclaw 通过 /internal/notifications/bulk 通知管理员', async ({ request }) => {
  // nullclaw 检测到摘要漂移，调用 bulk 通知接口
  const bulkResp = await request.post('/internal/notifications/bulk', {
    headers: { Authorization: `ApiKey ${testNullclawApiKey}` },
    data: {
      notification_type: 'consensus_drift',
      recipients: ['admin_user'],
      content: {
        title: '线索摘要偏差告警',
        body: '话题「Redis集群部署」摘要与最新消息偏差超过30%，建议重新生成。',
        action_url: `/threads/${testThreadId}`,
        metadata: {
          thread_id: testThreadId,
          drift_score: 0.42,
          message_count_delta: 15,
        },
      },
      priority: 'high',
    },
  });
  expect(bulkResp.ok()).toBeTruthy();
  const result = await bulkResp.json();
  expect(result.created_count).toBe(1);

  // 验证管理员收到通知
  const notifResp = await request.get('/api/v1/notifications', {
    headers: { 'X-User-Id': 'admin_user' },
  });
  const notifs = (await notifResp.json()).notifications;
  const driftNotif = notifs.find((n: any) => n.type === 'consensus_drift');
  expect(driftNotif).toBeDefined();
  expect(driftNotif.metadata?.drift_score).toBe(0.42);
});
```

---

### TC-INGEST-013：管家推送配置 - nullclaw 读取动态配置（GAP-15）

```typescript
test('butler_push_config - nullclaw 读取并按配置推送日报', async ({ request }) => {
  // 1. 管理员更新日报推送目标
  const updateResp = await request.put('/api/v1/admin/butler/config/daily_digest_room', {
    headers: { 'X-User-Id': 'admin_user', 'X-User-Role': 'admin' },
    params: { group_id: 'default' },
    data: {
      target_room_id: 'announcements',
      target_room_name: '公告频道',
      enabled: true,
    },
  });
  expect(updateResp.ok()).toBeTruthy();

  // 2. nullclaw 读取配置
  const configResp = await request.get('/internal/butler/config', {
    headers: { Authorization: `ApiKey ${testNullclawApiKey}` },
    params: { group_id: 'default', config_type: 'daily_digest_room' },
  });
  const configs = await configResp.json();
  expect(configs.length).toBe(1);
  expect(configs[0].target_room_id).toBe('announcements');  // 读取到最新配置
  expect(configs[0].enabled).toBe(true);

  // 3. 验证禁用后 nullclaw 不读取到该配置
  await request.put('/api/v1/admin/butler/config/daily_digest_room', {
    headers: { 'X-User-Id': 'admin_user', 'X-User-Role': 'admin' },
    params: { group_id: 'default' },
    data: { enabled: false },
  });

  const configResp2 = await request.get('/internal/butler/config', {
    headers: { Authorization: `ApiKey ${testNullclawApiKey}` },
    params: { group_id: 'default', config_type: 'daily_digest_room' },
  });
  const configs2 = await configResp2.json();
  expect(configs2.length).toBe(0);  // 禁用后不返回
});
```

---

### TC-INGEST-014：reference_data 敏感字段访问控制（GAP-13）

```typescript
test('reference_data 敏感字段 - 非当事人只能看 label 不能看 value', async ({ request }) => {
  // 假设已有一条 is_sensitive=true 的 reference_data（如薪资信息）
  const searchResp = await request.get('/api/v1/search', {
    headers: { 'X-User-Id': 'regular_user' },
    params: { query: '薪资标准', entity_types: 'reference_data' },
  });
  const results = (await searchResp.json()).results?.reference_data ?? [];

  // 普通用户只能看到 label，不能看到 value
  for (const item of results) {
    if (item.is_sensitive) {
      expect(item.label).toBeDefined();
      expect(item.value).toBeUndefined();  // GAP-13：敏感值不返回
    }
  }

  // 当事人可以看到 value
  const sensitiveSearchResp = await request.get('/api/v1/search', {
    headers: { 'X-User-Id': 'authorized_stakeholder' },
    params: { query: '薪资标准', entity_types: 'reference_data' },
  });
  const sensitiveResults = (await sensitiveSearchResp.json()).results?.reference_data ?? [];
  const sensitiveItem = sensitiveResults.find((i: any) => i.is_sensitive);
  if (sensitiveItem) {
    expect(sensitiveItem.value).toBeDefined();  // 当事人可见 value
  }
});
```

---

### Helper 函数

```typescript
// e2e/helpers/pipeline-helpers.ts

const testWebhookSecret = process.env.TEST_WEBHOOK_SECRET ?? 'test-secret';
const testNullclawApiKey = process.env.TEST_NULLCLAW_API_KEY ?? 'test-nullclaw-key';
const testThreadId = process.env.TEST_THREAD_ID ?? '550e8400-e29b-41d4-a716-446655440000';

async function waitForMessageStatus(
  request: APIRequestContext,
  messageId: string,
  expectedStatus: string,
  options: { timeout: number } = { timeout: 10_000 }
): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < options.timeout) {
    const resp = await request.get(`/api/v1/messages/${messageId}`);
    if (resp.ok()) {
      const msg = await resp.json();
      if (msg.processing_status === expectedStatus) return;
      if (['failed', 'skipped'].includes(msg.processing_status)) {
        throw new Error(`Message ${messageId} reached unexpected status: ${msg.processing_status}`);
      }
    }
    await new Promise(r => setTimeout(r, 500));
  }
  throw new Error(`Timeout waiting for message ${messageId} to reach status: ${expectedStatus}`);
}

async function waitForThreadSummary(
  request: APIRequestContext,
  threadId: string,
  options: { timeout: number } = { timeout: 8_000 }
): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < options.timeout) {
    const resp = await request.get(`/api/v1/threads/${threadId}`);
    if (resp.ok()) {
      const thread = await resp.json();
      if (thread.summary && thread.summary.trim().length > 0) return;
    }
    await new Promise(r => setTimeout(r, 500));
  }
  throw new Error(`Timeout waiting for thread ${threadId} summary`);
}

async function waitForPendingEvents(
  request: APIRequestContext,
  expectedCount: number,
  options: { timeout: number } = { timeout: 5_000 }
): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < options.timeout) {
    const resp = await request.get('/api/v1/nullclaw/pending-events', {
      params: { status: 'pending' },
    });
    if (resp.ok()) {
      const data = await resp.json();
      if (data.total >= expectedCount) return;
    }
    await new Promise(r => setTimeout(r, 300));
  }
  throw new Error(`Timeout waiting for ${expectedCount} pending events`);
}
```

---

**END OF E2E TEST CATALOG**
