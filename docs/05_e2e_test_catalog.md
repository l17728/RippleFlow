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

**END OF E2E TEST CATALOG**
