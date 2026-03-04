# RippleFlow 设计文档专家审查报告（深度版）

**审查日期**: 2026-03-02  
**审查范围**: 全部设计文档  
**审查视角**: 产品经理 / 软件架构师 / 系统设计专家 / 信息学专家  

---

## 一、整体评价

### 1.1 文档体系成熟度评估

| 维度 | 评分 | 说明 |
|------|------|------|
| **需求完整性** | ⭐⭐⭐⭐☆ | 核心场景覆盖全面，边缘场景定义不足 |
| **架构合理性** | ⭐⭐⭐⭐⭐ | 六阶段流水线设计精妙，服务边界清晰 |
| **技术可行性** | ⭐⭐⭐⭐☆ | 技术栈选型务实，LLM调用成本需优化 |
| **用户体验** | ⭐⭐⭐☆☆ | 基础交互完备，缺乏高级交互设计 |
| **可扩展性** | ⭐⭐⭐⭐☆ | 模块化设计良好，缺乏弹性伸缩规划 |
| **运维友好度** | ⭐⭐⭐☆☆ | 基础监控有，但深度可观测性不足 |

### 1.2 设计亮点

1. **六阶段处理流水线**：边界清晰，每阶段职责明确，Pipeline模式可维护性强
2. **敏感授权机制**：7天升级机制、脱敏支持，隐私保护完善，符合企业级要求
3. **AI管家架构**：提示词分级、自省机制、权限层级设计创新，具有差异化竞争力
4. **Protocol接口定义**：Python类型约束，便于mock测试，符合SOLID原则
5. **用户手册**：Use Case完整，Mermaid图清晰，可直接用于测试用例构建

---

## 二、产品体验改进建议

### 2.1 时间窗口机制的风险与优化

#### 问题描述
当前时间窗口设计：
- QA/FAQ: 90天
- Bug案例: 90天
- 待办: 30天
- 知识分享: 180天
- 技术决策/参考信息: 永久

#### 核心风险
```
风险1: 信息丢失
- 90天后FAQ自动不可检索
- 经典Bug解决方案可能无法查找
- 团队成员误以为"系统没记录"

风险2: 知识孤岛
- 长期项目的历史决策难以追溯
- 跨时间窗口的关联性丢失

风险3: 用户困惑
- 用户不知道有时间窗口限制
- 搜索结果不完整导致信任度下降
```

#### 改进建议

**方案A: 分层存储策略（推荐）**
```
热数据 (最近90天): PostgreSQL全文检索
  ↓ 自动归档
温数据 (90天-2年): Elasticsearch/ClickHouse
  ↓ 手动审核
冷数据 (2年以上): 对象存储(S3) + 元数据索引

用户查询时:
- 默认搜索热数据
- 自动提示:"发现3条历史记录，点击查看"
- 允许用户主动搜索全量数据
```

**方案B: 智能保鲜机制**
```
规则1: 被引用次数>5次的线索，自动延长窗口至1年
规则2: 用户收藏的线索，永久保留
规则3: 技术决策/故障案例类别，永久保留摘要
规则4: 每周自动识别"即将过期的高价值线索"，提醒当事人review
```

**实现建议**:
1. 在topic_threads表增加`archive_status`字段
2. 新增ArchiveWorker定期处理过期数据
3. 搜索API支持`include_archived=true`参数

---

### 2.2 敏感授权机制的优化

#### 问题描述
当前机制：
- 7天未处理自动升级管理员
- 需全部当事人授权
- 任一当事人拒绝则永不处理

#### 核心问题
```
问题1: 7天周期过长
- 创业团队节奏快，7天可能已产生大量待授权堆积
- 当事人可能已忘记讨论上下文

问题2: 一票否决过于严格
- 某当事人恶意/误操作拒绝，导致重要信息丢失
- 实际场景中可能存在"部分敏感"内容

问题3: 缺乏分级处理
- 所有敏感内容一视同仁
- 无法区分"轻微敏感"vs"高度敏感"
```

#### 改进建议

**分级敏感策略**:
```yaml
敏感级别定义:
  L1-轻微敏感:
    - 示例: 薪资范围讨论、一般性绩效反馈
    - 授权策略: 任一当事人授权即可
    - 升级时间: 3天
    - 默认处理: 脱敏后入库(替换为"某员工")
    
  L2-中等敏感:
    - 示例: 具体薪资数字、晋升决策
    - 授权策略: 当事人>50%授权
    - 升级时间: 5天
    - 默认处理: 等待授权
    
  L3-高度敏感:
    - 示例: 离职谈判、纪律处分、法律纠纷
    - 授权策略: 需全部当事人授权
    - 升级时间: 7天
    - 默认处理: 严格等待，永不自动处理
```

**智能脱敏**:
```
L1敏感内容自动脱敏示例:
原文: "李四这次绩效C，工资调整-10%"
脱敏: "某员工这次绩效评级较低，薪资有所调整"

保留价值:
- 团队了解"近期有绩效调整"
- 不暴露具体人员和数字
- 可作为HR政策类知识沉淀
```

---

### 2.3 机器人交互体验升级

#### 问题描述
当前机器人能力：
- 单次问答
- 简单的追问提示
- 无记忆能力

#### 改进建议

**多轮对话支持**:
```
场景: 技术问题排查

用户: @机器人 Redis连接超时怎么办？
机器人: [回答搭建步骤]

用户: 第2个方案的具体配置是什么？
机器人: 明白，您想了解"连接池配置方案"的具体参数...
       [展示详细配置]
       
用户: 这个配置的适用版本是？
机器人: 该配置适用于Redis 6.x版本...

技术实现:
- 在Redis中维护对话状态(5分钟过期)
- 使用thread_id追踪上下文
- 支持"返回上一步"、"重新开始"
```

**主动推荐机制**:
```
场景: 用户查询后，系统智能推荐

用户: @机器人 JWT怎么配置？
机器人: [回答JWT配置]
        💡 您可能还想了解:
        • "JWT Token有效期设置"
        • "JWT刷新机制实现"  
        • "JWT vs Session选型对比"

推荐算法:
- 协同过滤: 看过A的人还看了B
- 内容相似: 同一话题下的其他线索
- 时序相关: 该决策后的后续讨论
```

**富交互卡片**:
```yaml
当前响应:
  纯文本列表，信息密度低

改进方案:
  类型1-决策卡片:
    - 标题: 技术决策
    - 标签: Redis, 缓存, 架构
    - 核心结论: 使用Redis Cluster
    - 决策人: 张三、李四
    - 时间: 2024-11-12
    - 操作: [查看详情] [相关讨论]
    
  类型2-FAQ卡片:
    - 问题: Redis连接超时怎么处理？
    - 答案摘要: 检查max_connections...
    - 解决率: ★★★★☆ (被引用5次)
    - 操作: [详细步骤] [标记有用]
    
  类型3-参考信息卡片:
    - 环境: 测试环境
    - 类型: Redis
    - 地址: 192.168.1.100:6379
    - 一键复制按钮
    - 过期提醒: ⚠️ 90天未更新
```

---

### 2.4 通知系统的智能化

#### 问题描述
当前通知:
- 敏感授权待处理
- 待办到期提醒
- 每周快报

#### 改进建议

**智能免打扰**:
```
学习用户行为:
- 用户A通常在9:00-10:00查看系统
- 用户B通常在14:00-15:00处理待办

优化策略:
- 在活跃时段前5分钟推送通知
- 避免深夜/午休推送
- 重要程度分级:
  • 紧急: 立即推送(待办今天到期)
  • 重要: 活跃时段推送(敏感授权)
  • 一般: 每日汇总推送(每周快报)
```

**通知疲劳控制**:
```
问题: 某天敏感讨论多，用户收到10+授权请求

解决方案:
1. 批量授权界面:
   "您有5条敏感内容待授权，点击查看详情"
   [一键授权全部] [逐条查看]

2. 相似内容聚合:
   "关于'绩效调整'的3条相关讨论，是否统一授权？"

3. 智能摘要:
   不再逐条通知，改为:
   "今天有3条您的敏感内容待处理: 2条HR相关，1条项目相关"
```

---

## 三、架构设计改进建议

### 3.1 LLM调用成本优化

#### 问题分析
当前架构: 每个消息经过6阶段，每阶段1-2次LLM调用
```
单条消息处理成本:
- Stage 0: 1次 × 400 tokens
- Stage 1: 1次 × 200 tokens  
- Stage 2: 1次 × 500 tokens
- Stage 3: 1次 × 800 tokens
- Stage 4: 1次 × 600 tokens
- Stage 5: 1次 × 1000 tokens
合计: ~3500 tokens/消息

按10人团队，每天500条消息:
- 每日token消耗: 1,750,000
- 每月token消耗: 52,500,000
- 按GLM-4-plus价格估算，月成本约数千元
```

#### 优化策略

**策略1: 规则+模型混合过滤**
```python
# Stage 1 噪声过滤优化
# 先规则过滤，再模型确认

def check_noise_optimized(content: str) -> NoiseCheckResult:
    # 规则1: 长度<5字符 → 直接判定噪声
    if len(content.strip()) < 5:
        return NoiseCheckResult(is_noise=True, reason="过短")
    
    # 规则2: 纯表情/符号 → 直接判定噪声
    if is_emoji_only(content):
        return NoiseCheckResult(is_noise=True, reason="纯表情")
    
    # 规则3: 黑名单关键词匹配
    noise_keywords = ["ok", "收到", "好的", "👍", "+1"]
    if content.strip().lower() in noise_keywords:
        return NoiseCheckResult(is_noise=True, reason="常见短回复")
    
    # 规则无法确定，再走LLM
    return llm_check_noise(content)

# 预计减少30-40%的Stage 1 LLM调用
```

**策略2: 批量处理**
```python
# 当前: 每条消息独立调用LLM
# 优化: 10条消息批量处理

def batch_classify(messages: List[str]) -> List[ClassificationResult]:
    # 单次prompt处理多条
    prompt = f"""
    对以下{len(messages)}条消息进行分类，返回JSON数组:
    
    {format_messages(messages)}
    
    输出格式:
    [
      {{"msg_idx": 0, "categories": [...]}},
      {{"msg_idx": 1, "categories": [...]}},
      ...
    ]
    """
    return call_llm(prompt)

# 预计减少50-60%的Stage 2调用次数
```

**策略3: 缓存机制**
```python
# 相似内容复用结果
from sentence_transformers import SentenceTransformer

class LLMCache:
    def __init__(self):
        self.encoder = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
        self.cache = {}  # embedding -> result
    
    async def get_or_compute(self, content: str, compute_fn) -> Any:
        embedding = self.encoder.encode(content)
        
        # 查找相似内容
        for cached_emb, result in self.cache.items():
            similarity = cosine_similarity(embedding, cached_emb)
            if similarity > 0.95:  # 阈值可调
                return result  # 命中缓存
        
        # 未命中，执行LLM调用
        result = await compute_fn(content)
        self.cache[embedding] = result
        return result

# 适用于: Stage 0(敏感检测)、Stage 1(噪声过滤)
# 预计缓存命中率: 20-30%（群聊很多相似短消息）
```

**策略4: 模型降级策略细化**
```python
# 根据任务复杂度选择模型
MODEL_SELECTION = {
    # 高风险任务：必须用最强模型
    "stage0_sensitive_high": "glm-4-plus",  # 涉及法律风险的敏感内容
    "stage5_summary_conflict": "glm-4-plus",  # 检测到冲突时的摘要修正
    
    # 中等风险：允许轻度降级
    "stage2_classify_clear": "glm-4-air",  # 明显类别特征时
    "stage3_match_thread_strong": "glm-4-air",  # 高置信度匹配
    
    # 低风险：可用快速模型
    "stage1_noise_short": "glm-4-flash",  # 短消息噪声检测
    "qa_keywords_simple": "glm-4-flash",  # 简单关键词提取
}

# 动态选择逻辑
async def select_model(stage: str, content: str, context: dict) -> str:
    # 根据内容复杂度判断
    if len(content) < 50 and stage == "stage1_noise":
        return "glm-4-flash"
    
    # 根据历史准确率判断
    if context.get("historical_accuracy", 1.0) > 0.95:
        return "glm-4-air"  # 该场景历史表现好，降级
    
    return MODEL_REQUIREMENTS[stage]  # 默认要求
```

**成本优化效果预估**:
```
优化前月成本: 100%
优化后期望成本: 
  - 规则过滤: -15%
  - 批量处理: -20%
  - 缓存机制: -10%
  - 模型降级: -15%
合计节省: ~60%
```

---

### 3.2 全文检索性能优化

> ⚠️ **重要说明**：RippleFlow 的核心架构约束是**不使用向量数据库/embedding 检索**（见 `00_overview.md` 设计约束）。本节的方案 B（混合检索/embedding）和向量数据库建议（方案 A 阶段 3）仅作为未来可选优化路径的参考，**不代表当前架构决策**。若未来确实需要引入，须在团队评审后再决策。当前推荐方案 A 阶段 1-2 和方案 C（索引优化）。

#### 问题分析
```
当前方案: PostgreSQL pg_trgm + tsvector（或 SQLite FTS5）
- 适合: 数据量<100万条
- 风险: 数据量增长后性能急剧下降
- 问题: 不支持语义搜索（但通过 LLM 综合回答可一定程度弥补）

未来痛点:
- 10人团队1年可能产生10-20万条消息
- 3年数据量可达50-100万条
- 全文检索响应时间从100ms增至2s+
```

#### 优化建议

**方案A: 引入专用搜索引擎（推荐）**
```yaml
架构升级:
  阶段1 (0-6个月):
    - 保持PostgreSQL全文检索
    - 增加Materialized View优化查询
    
  阶段2 (6-12个月，数据量>10万):
    - 引入Elasticsearch或Typesense
    - 同步策略:
        PostgreSQL -> Debezium CDC -> Kafka -> Elasticsearch
    - 保留PostgreSQL作为主存储
    
  阶段3 (12个月+，数据量>50万):
    - Elasticsearch分片优化
    - 冷热数据分离
    - 考虑向量数据库(Milvus/Pinecone)支持语义搜索
```

**方案B: 混合检索策略**
```python
# 当前: 仅关键词检索
# 优化: 关键词 + 语义混合

class HybridSearchService:
    def __init__(self):
        self.pg_search = PostgreSQLSearch()
        self.embedding_model = SentenceTransformer('BAAI/bge-large-zh')
        # 注: embedding可在本地计算，不依赖LLM API
    
    async def search(self, query: str, top_k: int = 10) -> List[SearchHit]:
        # 1. 关键词检索
        keyword_results = await self.pg_search.full_text_search(query, top_k=20)
        
        # 2. 语义检索(使用embedding)
        query_embedding = self.embedding_model.encode(query)
        semantic_results = await self.vector_search(query_embedding, top_k=20)
        
        # 3. 混合排序(RRF算法)
        combined = self.reciprocal_rank_fusion(
            keyword_results, 
            semantic_results,
            weights=[0.7, 0.3]  # 关键词权重更高
        )
        
        return combined[:top_k]

# 优势: 
# - 解决同义词问题("Redis超时" vs "Redis连接超时")
# - 支持自然语言理解
# - embedding计算成本远低于LLM调用
```

**方案C: 索引优化**
```sql
-- 当前索引可能不足
-- 优化建议:

-- 1. 复合索引
CREATE INDEX CONCURRENTLY idx_thread_search_composite 
ON topic_threads USING GIN(search_vector, category, last_message_at);

-- 2. 分区表(按时间)
CREATE TABLE topic_threads_y2024m03 PARTITION OF topic_threads
FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');

-- 3. 预计算热数据
CREATE MATERIALIZED VIEW hot_threads AS
SELECT * FROM topic_threads 
WHERE last_message_at > NOW() - INTERVAL '90 days'
ORDER BY message_count DESC;

-- 4. 查询优化
-- 使用EXPLAIN ANALYZE定期检查慢查询
-- 设置shared_buffers = 25% of RAM
-- 设置effective_cache_size = 50% of RAM
```

---

### 3.3 消息处理可靠性提升

#### 问题描述
```
当前Celery队列:
- 消息处理失败可能丢失
- 无限重试可能导致死循环
- 缺乏死信队列(Dead Letter Queue)
- 监控告警不足
```

#### 改进建议

**增强消息处理流水线**:
```python
# 改进的ProcessingPipeline配置
from celery import Celery
from kombu import Queue, Exchange

app = Celery('rippleflow')

# 定义多队列
app.conf.task_queues = (
    Queue('high_priority', Exchange('high'), routing_key='high'),
    Queue('normal', Exchange('normal'), routing_key='normal'),
    Queue('dlq', Exchange('dlq'), routing_key='dlq'),  # 死信队列
)

@app.task(
    bind=True,
    max_retries=3,
    default_retry_delay=60,
    retry_backoff=True,
    retry_backoff_max=600,
    retry_jitter=True,
    acks_late=True,  # 确认后置，防止丢消息
    reject_on_worker_lost=True,
)
def process_message(self, message_id: str):
    try:
        # 处理逻辑
        result = run_processing_pipeline(message_id)
        return result
    except RetryableError as e:
        # 可重试错误
        if self.request.retries < 3:
            raise self.retry(exc=e, countdown=60 * (2 ** self.request.retries))
        else:
            # 重试耗尽，转入死信队列
            move_to_dlq(message_id, str(e))
    except NonRetryableError as e:
        # 不可重试错误，直接标记失败
        mark_message_failed(message_id, str(e))
        # 发送告警
        send_alert(f"Message {message_id} processing failed: {e}")
```

**死信队列处理**:
```python
# DLQ消费和人工介入
@app.task(queue='dlq')
def process_dlq(message_id: str, error_info: str):
    # 1. 记录到专门的失败消息表
    FailedMessage.objects.create(
        message_id=message_id,
        error=error_info,
        failed_at=timezone.now(),
        retry_count=3
    )
    
    # 2. 发送告警给管理员
    send_admin_alert(
        title=f"消息处理失败: {message_id}",
        content=f"错误信息: {error_info}\n请登录后台处理",
        action_url=f"/admin/failed-messages/{message_id}"
    )
    
    # 3. 管理员可选择:
    # - 重新处理
    # - 标记跳过
    # - 人工处理并入库

# 管理后台界面
def admin_retry_failed_message(request, message_id):
    failed_msg = FailedMessage.objects.get(message_id=message_id)
    
    # 重新入队
    process_message.apply_async(args=[message_id], queue='high_priority')
    
    failed_msg.status = 'retried'
    failed_msg.save()
    
    return JsonResponse({"status": "retried"})
```

**处理状态可视化**:
```
管理后台新增"消息处理监控"页面:

实时看板:
- 待处理: 123条
- 处理中: 5条
- 今日成功: 456条
- 今日失败: 2条
- 平均处理时长: 2.3s

失败消息列表:
| 消息ID | 内容预览 | 失败原因 | 重试次数 | 操作 |
|--------|----------|----------|----------|------|
| msg_001 | Redis超时... | LLM超时 | 3/3 | [重试] [跳过] |
| msg_002 | 部署问题... | JSON解析失败 | 3/3 | [查看] [跳过] |
```

---

### 3.4 数据归档策略

#### 问题描述
```
风险:
- PostgreSQL单表数据量持续增长
- 查询性能下降
- 备份恢复时间增长
- 存储成本上升
```

#### 建议方案

**三级存储架构**:
```
L1-热数据 (0-90天):
  存储: PostgreSQL主库
  访问: 实时查询
  索引: 完整索引
  
L2-温数据 (90天-2年):
  存储: PostgreSQL从库 / ClickHouse
  访问: 延迟可接受(秒级)
  索引: 精简索引(仅关键字段)
  触发: 自动归档任务
  
L3-冷数据 (2年以上):
  存储: 对象存储(S3/MinIO) + 元数据索引
  访问: 需手动申请恢复
  压缩: Gzip压缩存储
  成本: 最低
```

**归档实现**:
```python
# Celery定时任务
def archive_old_threads():
    cutoff_date = timezone.now() - timedelta(days=90)
    
    # 1. 查询待归档数据
    old_threads = Thread.objects.filter(
        last_message_at__lt=cutoff_date,
        archive_status='active'
    ).exclude(
        category__in=['tech_decision', 'reference_data']  # 永久保留类别
    ).exclude(
        is_favorite=True  # 用户收藏的不归档
    )
    
    for thread in old_threads:
        # 2. 序列化到对象存储
        data = serialize_thread(thread)
        s3_client.put_object(
            Bucket='rippleflow-archive',
            Key=f"threads/{thread.id}.json.gz",
            Body=gzip.compress(json.dumps(data).encode())
        )
        
        # 3. 更新元数据(保留摘要用于检索)
        thread.archive_status = 'archived'
        thread.full_content = None  # 释放空间
        thread.save()
        
        # 4. 保留搜索索引(仅标题+摘要)
        SearchIndex.update(thread, partial=True)

# 恢复归档数据
def restore_archived_thread(thread_id: str):
    # 从S3读取
    obj = s3_client.get_object(
        Bucket='rippleflow-archive',
        Key=f"threads/{thread_id}.json.gz"
    )
    data = json.loads(gzip.decompress(obj['Body'].read()))
    
    # 临时恢复到数据库
    return data
```

---

## 四、轻量级分级索引架构（替代Elasticsearch）

基于进一步讨论，我们认为应该采用**轻量级的分级索引机制**而非引入Elasticsearch等重型搜索引擎。该方案更符合RippleFlow"减少冗余、提取精华"的设计理念。

### 4.1 设计理念

```
传统数据库思路:
原始消息 ──→ 存储 ──→ 检索时遍历大量数据
                    (数据量线性增长)

分级索引思路:
原始消息 ──→ 实时摘要 ──→ 周期性压缩(compact)
                         (信息量对数增长)
                              ↓
                    层级化知识图谱
                         (常数访问)
```

**核心原则**：
- 模仿人类认知系统的记忆分层机制
- 及时总结归并，避免信息冗余
- 周期性compact，提取压缩信息
- 文件组织有层次，避免过多过大

### 4.2 三级记忆架构

```yaml
.knowledge/                      # 知识库根目录
├── L1-active/                   # 活跃层（工作记忆）
│   ├── threads/                 # 当前活跃话题
│   │   ├── 2024-03-thread-001.yaml
│   │   └── 2024-03-thread-002.yaml
│   └── index.yaml              # L1索引（最近30天）
│
├── L2-knowledge/                # 知识层（长期记忆）
│   ├── by-category/
│   │   ├── tech-decision/       # 技术决策合集
│   │   │   ├── redis-cluster.yaml
│   │   │   └── auth-system.yaml
│   │   ├── qa-faq/              # FAQ合集
│   │   └── reference/           # 参考信息合集
│   └── index.yaml              # L2索引
│
└── L3-core/                     # 核心层（语义记忆）
    ├── knowledge-graph.yaml     # 知识图谱
    ├── decision-log.yaml        # 关键决策时间线
    ├── tech-stack.yaml          # 技术栈演进
    └── index.yaml              # L3总索引
```

**各层定位**：

| 层级 | 时间窗口 | 内容特征 | 查询复杂度 | 存储方式 |
|------|----------|----------|------------|----------|
| **L1活跃层** | 0-30天 | 详细、完整、实时 | O(n) | YAML文件 |
| **L2知识层** | 30天-2年 | 领域聚合、结构化 | O(log n) | YAML文件 |
| **L3核心层** | 永久 | 抽象、关联、推理 | O(1) | 知识图谱 |

### 4.3 文件大小控制

```yaml
文件大小限制:
  L1索引: < 50KB（活跃话题<100个）
  L2节点: < 100KB（单个领域知识）
  L3核心: < 200KB（知识图谱）
  单个线索: < 500KB

控制策略:
  1. 分片:
     - L2节点超过100KB时，按子主题拆分
  2. 压缩存储:
     - 原始消息用gzip压缩
     - 索引文件保持明文
  3. 定期清理:
     - 已完全压缩到L3的L2节点，删除详细内容
     - 归档超过1年的原始消息
```

### 4.4 Compact（压缩）机制

```python
COMPACT_RULES = {
    "L1_to_L2": {
        "trigger": "thread.last_message_at > 30 days ago",
        "action": "提取核心知识到L2节点",
        "preserve": "保留原始消息链接"
    },
    "L2_to_L3": {
        "trigger": "L2 node not updated > 90 days",
        "action": "提取关键决策到L3图谱",
        "preserve": "保留L2节点索引"
    },
    "L3_evolution": {
        "trigger": "monthly",
        "action": "更新知识图谱和决策时间线",
        "preserve": "历史版本归档"
    }
}
```

---

## 五、四大类信息提取架构

从聊天记录中可提取四类核心信息：知识库、任务待办、事件线索、协作网络。

### 5.1 信息分类与分级映射

```
┌─────────────────────────────────────────────────────────────┐
│                     原始聊天记录 (Raw Data)                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────────┼─────────────────────┐
        ↓                     ↓                     ↓
┌───────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  任务与待办    │   │   事件与线索     │   │   关系网络       │
│  (Actionable) │   │  (Contextual)   │   │  (Relational)   │
└───────────────┘   └─────────────────┘   └─────────────────┘
        ↓                     ↓                     ↓
┌─────────────────────────────────────────────────────────────┐
│                     知识库类 (Knowledge)                       │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 知识库类信息 (Knowledge Assets)

**包含内容**：
- **FAQ与解决方案**：常见问题及对应解答
- **经验总结与最佳实践**：项目复盘、工作方法
- **术语与规则说明**：专业术语、业务流程
- **外部资源归档**：行业报告、政策文件、竞品分析

**提取Prompt示例**：

```yaml
knowledge_extraction:
  qa_faq:
    trigger_keywords: ["问题", "怎么办", "如何解决", "报错"]
    extraction_prompt: |
      从对话中提取问题-解答对：
      {
        "question": "问题描述",
        "answer": "详细解答",
        "confidence": 0.9
      }
  
  best_practice:
    trigger_keywords: ["经验", "总结", "建议", "最佳"]
    extraction_prompt: |
      提取经验总结：
      {
        "title": "经验标题",
        "key_points": ["要点1", "要点2"],
        "applicable_scenarios": "适用场景"
      }
```

**文件组织**：
```yaml
.knowledge/L2-knowledge/
├── qa-faq/
│   ├── redis-troubleshooting.yaml
│   └── jwt-implementation.yaml
├── best-practices/
│   ├── code-review-guidelines.yaml
│   └── client-communication.yaml
└── glossary/
    ├── tech-terms.yaml
    └── business-rules.yaml
```

### 5.3 任务与待办 (Action Items)

**提取维度**：

```yaml
task_extraction:
  explicit_tasks:          # 显性任务
    patterns:
      - "@{person} {action} {deadline}"
      - "{person} {action} before {time}"
    examples:
      - "@张三 周三前把项目方案发给我"
  
  implicit_commitments:    # 隐性承诺
    patterns:
      - "我{time}会{action}"
      - "回头我{action}"
    examples:
      - "我回头联系客户确认合作细节"
  
  multi_step_tasks:        # 多步骤事项
    extraction: |
      拆解项目计划为具体任务步骤
```

**状态跟踪**：

```yaml
task_states:
  identified → confirmed → in_progress → completed → verified → archived

completion_signals:        # 自动检测完成信号
  - "已完成"
  - "搞定了"
  - "done"
  - "✅"
```

### 5.4 事件与线索 (Event Threads)

**事件类型**：

```yaml
event_types:
  milestone:               # 项目里程碑
    indicators: ["立项", "评审通过", "上线", "发布"]
  
  issue_resolution:        # 问题处理全过程
    tracking: |
      issue → investigation → resolution → prevention
  
  customer_journey:        # 客户互动轨迹
    tracking: |
      需求提出 → 方案讨论 → 实施交付 → 反馈迭代
```

**线索追踪算法**：

```python
class EventThreadTracker:
    def track_thread(self, messages: List[Message]):
        # 1. 识别线索起始
        if self.is_thread_start(messages[0]):
            thread = EventThread(
                start_message=messages[0],
                type=self.classify_thread_type(messages)
            )
        
        # 2. 跟踪线索发展
        for msg in messages[1:]:
            if new_state := self.detect_state_change(msg):
                thread.add_state_transition(new_state, msg)
            if decision := self.extract_decision(msg):
                thread.add_decision_point(decision)
        
        # 3. 检测线索结束
        if self.is_thread_resolved(messages[-1]):
            thread.mark_resolved()
        
        return thread
```

### 5.5 关系与协作网络 (Collaboration Graph)

**关系类型**：

```yaml
relation_types:
  communication:           # 沟通关系
    - frequent_collaborators    # 频繁协作
    - information_bridge        # 信息桥梁
    - knowledge_expert          # 领域专家
  
  task_based:              # 任务关系
    - task_assigner             # 任务分配者
    - task_executor             # 任务执行者
    - reviewer                  # 评审者
  
  knowledge_based:         # 知识关系
    - knowledge_contributor     # 知识贡献者
    - question_asker            # 提问者
    - answer_provider           # 解答者

# 关系权重计算
relation_weights:
  @提及: 3.0
  回复消息: 2.0
  共同参与话题: 1.5
  同时在线: 0.5
```

**协作网络分析**：

```python
class CollaborationAnalyzer:
    def analyze_network(self, time_window: int = 30):
        # 1. 构建互动矩阵
        interaction_matrix = self.build_interaction_matrix(time_window)
        
        # 2. 识别关键角色
        roles = {
            'hub': self.identify_hubs(interaction_matrix),
            'bridge': self.identify_bridges(interaction_matrix),
            'expert': self.identify_experts(),
            'isolates': self.identify_isolates(interaction_matrix)
        }
        
        # 3. 检测协作模式
        patterns = {
            'cliques': self.find_cliques(),
            'bottlenecks': self.find_bottlenecks(),
            'efficiency': self.calculate_efficiency()
        }
        
        return CollaborationNetwork(roles=roles, patterns=patterns)
```

### 5.6 渐进式实施路线图

**Phase 1: 基础提取 (Week 1-2)**
- 显性任务提取
- 简单FAQ提取  
- 基础事件线索追踪

**Phase 2: 智能提升 (Week 3-4)**
- 隐性承诺识别
- 多步骤任务拆解
- 问题全流程跟踪

**Phase 3: 网络分析 (Week 5-6)**
- 互动频率统计
- @关系分析
- 专家识别

**Phase 4: 知识进化 (Week 7-8)**
- L1→L2自动compact
- L2→L3知识图谱构建
- 跨领域关联发现

---

## 六、关键技术改进建议（续）

### 4.1 引入事件溯源模式

#### 问题描述
```
当前: 直接更新topic_threads表
问题: 
- 无法回溯完整变更历史
- 调试困难
- 无法支持时间旅行查询(查看某时间点的状态)
```

#### 改进方案
```python
# 事件溯源实现
from dataclasses import dataclass
from typing import List

@dataclass
class ThreadEvent:
    event_id: str
    thread_id: str
    event_type: str  # created, message_added, summary_updated, merged
    payload: dict
    occurred_at: datetime
    actor_id: str

class EventStore:
    def append(self, event: ThreadEvent):
        # 只追加，不修改
        EventStoreModel.objects.create(**asdict(event))
    
    def get_events(self, thread_id: str) -> List[ThreadEvent]:
        return EventStoreModel.objects.filter(thread_id=thread_id).order_by('occurred_at')
    
    def get_state_at(self, thread_id: str, at_time: datetime) -> Thread:
        # 重放事件到指定时间点
        events = self.get_events(thread_id).filter(occurred_at__lte=at_time)
        return self.replay(events)
    
    def replay(self, events: List[ThreadEvent]) -> Thread:
        state = Thread()
        for event in events:
            state = apply_event(state, event)
        return state

# 使用场景
# 1. 查看话题完整生命周期
events = event_store.get_events(thread_id)
for event in events:
    print(f"{event.occurred_at}: {event.event_type} by {event.actor_id}")

# 2. 调试：查看某消息如何影响摘要
before_state = event_store.get_state_at(thread_id, message_sent_at - timedelta(seconds=1))
after_state = event_store.get_state_at(thread_id, message_sent_at + timedelta(minutes=5))
print(f"摘要变化: {before_state.summary} -> {after_state.summary}")

# 3. 撤销错误操作(支持undo)
last_event = events[-1]
if last_event.event_type == 'summary_updated' and last_event.actor_id == 'bot':
    # 发现Bot更新有误，撤销
    compensation_event = create_compensation_event(last_event)
    event_store.append(compensation_event)
```

---

### 4.2 实时数据流增强

#### 问题描述
```
当前: Webhook + 批量处理
问题: 缺乏实时性，无法实现实时协作功能
```

#### 改进方案
```python
# 引入WebSocket支持实时更新
from channels.generic.websocket import AsyncWebsocketConsumer

class ThreadConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.thread_id = self.scope['url_route']['kwargs']['thread_id']
        self.user = self.scope['user']
        
        # 加入线程组
        await self.channel_layer.group_add(
            f"thread_{self.thread_id}",
            self.channel_name
        )
        await self.accept()
    
    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            f"thread_{self.thread_id}",
            self.channel_name
        )
    
    # 接收消息更新广播
    async def thread_update(self, event):
        await self.send(text_data=json.dumps({
            'type': 'update',
            'thread_id': event['thread_id'],
            'change_type': event['change_type'],  # summary_updated, new_message
            'payload': event['payload'],
            'timestamp': event['timestamp']
        }))

# 在消息处理完成后广播
async def notify_thread_update(thread_id: str, change_type: str, payload: dict):
    channel_layer = get_channel_layer()
    await channel_layer.group_send(
        f"thread_{thread_id}",
        {
            'type': 'thread_update',
            'thread_id': thread_id,
            'change_type': change_type,
            'payload': payload,
            'timestamp': timezone.now().isoformat()
        }
    )

# 前端实时更新场景
"""
用户A: 在Dashboard查看话题详情
用户B: 在群聊中讨论该话题
Bot处理完成 -> 更新摘要
用户A的页面: 实时看到摘要更新提示
           "话题有更新，点击刷新查看"
"""
```

---

### 4.3 API设计优化

#### 问题描述
```
当前API存在一些问题:
1. 部分接口缺少分页
2. 错误信息不够友好
3. 缺乏API版本控制
4. 没有限流机制说明
```

#### 改进建议

**GraphQL支持（可选）**:
```python
# 对于复杂查询场景，提供GraphQL
import graphene

class Query(graphene.ObjectType):
    thread = graphene.Field(ThreadType, id=graphene.String(required=True))
    threads = graphene.List(ThreadType, 
        category=graphene.String(),
        assignee=graphene.String(),
        status=graphene.String()
    )
    
    def resolve_threads(self, info, **kwargs):
        # 前端可以灵活选择字段
        # 减少过度获取/获取不足
        return Thread.objects.filter(**kwargs)

# 前端查询示例
"""
query {
  threads(category: "tech_decision", status: "active") {
    id
    title
    summary
    stakeholderIds
    messages(limit: 5) {
      content
      sender
    }
  }
}
"""
```

**限流和熔断**:
```python
from django_ratelimit.decorators import ratelimit
from circuitbreaker import circuit

# 限流
@ratelimit(key='user', rate='100/m', method='POST')
@ratelimit(key='user', rate='1000/h', method='POST')
def search_api(request):
    pass

# 熔断（防止LLM服务故障拖垮系统）
@circuit(failure_threshold=5, recovery_timeout=60)
def call_llm_api(prompt: str) -> str:
    # 如果连续失败5次，熔断60秒
    return llm_client.chat.completions.create(...)
```

---

## 七、交互设计改进建议

### 7.1 Dashboard UX优化

#### 搜索体验
```yaml
当前搜索:
  输入 -> 点击搜索 -> 等待 -> 结果列表

改进方案:
  1. 实时搜索建议:
     输入"Redis"时:
     - 热门搜索: Redis配置, Redis集群, Redis优化
     - 最近搜索: Redis超时处理
     - 联想补全: Redis 连接池, Redis 主从复制

  2. 高级搜索面板:
     点击"高级搜索"展开:
     - 时间范围: [最近7天] [最近30天] [自定义]
     - 类别: [☑技术决策] [☑FAQ] [☐故障案例]
     - 人员: [张三] [李四] (多选)
     - 排序: [相关度▼] [时间▼] [热度▼]

  3. 搜索结果增强:
     每个结果卡片:
     - 标题 + 类别标签
     - 摘要高亮(匹配词标红)
     - 元信息: 👤3人参与 | 💬15条消息 | 📅2024-11-12
     - 快捷操作: [收藏] [分享] [标记有用]
     
  4. 搜索无结果优化:
     当前: "无结果"
     改进: "未找到相关内容，您可以:
          • 尝试其他关键词
          • 查看[相关话题]
          • 在群内提问并@机器人"
```

#### 话题详情页
```yaml
当前布局:
  标题
  摘要
  修改历史
  
改进布局:
  ┌──────────────────────────────────────────┐
  │ 标题 [技术决策] [Redis] [缓存]             │
  ├──────────────────────────────────────────┤
  │ 当前摘要                                  │
  │ [查看摘要演变] [修改]                     │
  ├──────────────────────────────────────────┤
  │ 📊 结构化信息                             │
  │ 决策: 使用Redis Cluster                   │
  │ 决策人: 张三、李四                        │
  │ 状态: 已实施                              │
  ├──────────────────────────────────────────┤
  │ 📈 数据洞察                               │
  │ 讨论热度: ████████░░ 8分                  │
  │ 被引用: 12次                              │
  │ 最后更新: 2天前                           │
  ├──────────────────────────────────────────┤
  │ 💬 关联消息(15条) [展开▼]                 │
  │ 最新消息: 李四: "已部署到生产环境"        │
  ├──────────────────────────────────────────┤
  │ 🔗 相关话题                               │
  │ • Redis性能优化指南                       │
  │ • 缓存一致性方案                          │
  ├──────────────────────────────────────────┤
  │ 👥 当事人                                 │
  │ 张三、李四、王五                          │
  └──────────────────────────────────────────┘
```

### 7.2 机器人交互增强

#### 富媒体响应
```yaml
当前: 纯文本
改进: 支持多种卡片类型

类型1-对比卡片:
  用户: "JWT和Session哪个好？"
  响应:
    ┌─────────────────────────────────────┐
    │ JWT vs Session 对比                  │
    ├──────────┬────────────┬─────────────┤
    │ 维度     │ JWT        │ Session     │
    ├──────────┼────────────┼─────────────┤
    │ 性能     │ ★★★★★     │ ★★★☆☆      │
    │ 安全性   │ ★★★☆☆     │ ★★★★☆      │
    │ 复杂度   │ ★★☆☆☆     │ ★★★☆☆      │
    ├──────────┴────────────┴─────────────┤
    │ [查看详细分析] [团队历史讨论]         │
    └─────────────────────────────────────┘

类型2-流程卡片:
  用户: "怎么排查Redis连接问题？"
  响应:
    ┌─────────────────────────────────────┐
    │ Redis连接问题排查流程                │
    │                                     │
    │ 1. 检查网络连通性 [详细] ✓           │
    │ 2. 验证连接参数 [详细] ⬅️            │
    │ 3. 查看连接数限制 [详细]             │
    │ 4. 检查防火墙配置 [详细]             │
    │                                     │
    │ [获取完整排查手册]                   │
    └─────────────────────────────────────┘

类型3-数据卡片:
  用户: "测试环境配置"
  响应:
    ┌─────────────────────────────────────┐
    │ 🖥️ 测试环境配置清单                   │
    │                                     │
    │ Redis: 192.168.1.100:6379 [复制]     │
    │ MySQL: 192.168.1.101:3306 [复制]     │
    │ API: http://api-test.internal [复制] │
    │                                     │
    │ ⚠️ Redis地址将于3天后更新             │
    │ [查看更新计划]                       │
    └─────────────────────────────────────┘
```

#### 对话上下文
```yaml
场景: 多轮技术咨询

用户: Redis集群怎么搭建？
机器人: [回答搭建步骤]

用户: 需要几个节点？
机器人: 明白，您想了解Redis集群的节点数量要求...
       [回答节点数量]
       
用户: 每个节点配置多少内存？
机器人: 关于Redis集群节点的内存配置建议...
       [回答内存配置]

技术实现:
  - 使用thread_id关联上下文
  - 在Redis中存储对话状态(5分钟过期)
  - 支持"返回上一步"、"重新开始"
  - 超过3轮未解决，建议转人工
```

---

## 八、设计理念补充建议

### 8.1 增加"知识生命周期管理"理念

```
知识不是静态的，应该全生命周期管理:

创建 -> 加工 -> 应用 -> 评估 -> 归档/更新

当前设计:
  强加工(6阶段流水线)
  弱评估(仅有问答反馈)
  无归档(时间窗口=软删除)
  
建议增强:
  1. 创建阶段:
     - 支持手动创建知识条目
     - 支持导入外部文档(Markdown/Confluence)
  
  2. 评估阶段:
     - 自动评估: 被引用次数、查看次数
     - 人工评估: 定期review标记"过时/需更新"
     - 满意度评分: 问答后评分
  
  3. 归档阶段:
     - 主动归档(非时间窗口自动过期)
     - 归档审核流程
     - 归档知识可恢复
```

### 8.2 强化"人机协作"理念

```
当前设计: AI主导(自动处理)
改进方向: 人机协作(AI辅助，人类决策)

具体措施:

1. AI建议，人类确认:
   - 敏感内容脱敏方案，人类可修改
   - 分类结果不确定时，人类选择
   - 摘要生成后，当事人可一键确认/修改

2. 人类主导，AI辅助:
   - 人工创建话题，AI自动关联相关消息
   - 人工标记重要信息，AI学习模式
   - 人工修正错误，AI记录并改进

3. 协作透明化:
   - Dashboard显示"AI处理了X条，人类修正了Y条"
   - 展示AI置信度，低置信度提醒人工介入
   - 提供"教AI学习"功能(纠正错误)
```

---

## 七、运维和监控建议

### 7.1 可观测性增强

```yaml
当前监控:
  - 基础API监控
  - 简单统计面板

建议增加:
  
业务指标监控:
  - 消息处理成功率(目标>99.5%)
  - 平均处理时长(目标<5s)
  - LLM调用成功率(目标>99%)
  - 问答满意度(目标>4.0/5)
  - 敏感授权处理及时率(目标>90%在3天内)
  
技术指标监控:
  - PostgreSQL慢查询(>1s)
  - Redis内存使用
  - Celery队列堆积数量
  - LLM API调用延迟
  - 错误日志聚合
  
用户行为监控:
  - DAU/MAU
  - 功能使用率
  - 搜索热词分析
  - 用户留存率
```

### 7.2 自动化运维

```python
# 自动化健康检查
@app.task
def health_check():
    issues = []
    
    # 1. 检查消息堆积
    pending_count = Message.objects.filter(status='pending').count()
    if pending_count > 1000:
        issues.append(f"消息堆积: {pending_count}条")
    
    # 2. 检查LLM API可用性
    try:
        test_llm_connection()
    except:
        issues.append("LLM API不可用")
    
    # 3. 检查数据库连接池
    if db_pool_usage > 80%:
        issues.append(f"数据库连接池使用率: {db_pool_usage}%")
    
    # 4. 检查敏感授权堆积
    old_pending = SensitiveAuth.objects.filter(
        created_at__lt=timezone.now() - timedelta(days=7)
    ).count()
    if old_pending > 10:
        issues.append(f"超期敏感授权: {old_pending}条")
    
    if issues:
        send_alert("系统健康检查异常", "\n".join(issues))
    
    return issues

# 每日自动报告
@app.task
def daily_report():
    report = {
        "date": timezone.now().date(),
        "messages_processed": Message.objects.filter(created_at__date=today).count(),
        "threads_created": Thread.objects.filter(created_at__date=today).count(),
        "qa_count": QASession.objects.filter(created_at__date=today).count(),
        "avg_satisfaction": calculate_avg_rating(),
        "pending_sensitive": SensitiveAuth.objects.filter(status='pending').count(),
        "system_health": run_health_check()
    }
    
    send_to_admin(report)
```

---

## 十、实施优先级建议

### 10.1 高优先级（MVP后尽快实施）

| 改进项 | 原因 | 预估工作量 |
|--------|------|------------|
| 规则+模型混合过滤 | 降低成本60%，效果明显 | 2天 |
| 增强消息处理可靠性 | 防止数据丢失，影响核心功能 | 3天 |
| 敏感分级策略 | 用户体验提升显著 | 2天 |
| 搜索体验优化 | 高频功能，直接影响满意度 | 3天 |
| 基础监控告警 | 运维必备 | 2天 |

### 10.2 中优先级（上线后1-3个月）

| 改进项 | 原因 | 预估工作量 |
|--------|------|------------|
| 引入Elasticsearch | 解决性能瓶颈 | 1周 |
| 机器人多轮对话 | 提升交互体验 | 4天 |
| 智能归档策略 | 长期可维护性 | 3天 |
| 富媒体响应卡片 | 提升用户体验 | 5天 |
| 事件溯源 | 调试和问题追踪 | 1周 |

### 10.3 低优先级（长期规划）

| 改进项 | 原因 | 预估工作量 |
|--------|------|------------|
| GraphQL API | 提升前端开发体验 | 1周 |
| WebSocket实时更新 | 高级功能 | 1周 |
| 混合检索(语义+关键词) | 搜索质量提升 | 1周 |
| 移动端适配 | 按需开发 | 2周 |

---

## 十一、总结

### 11.1 核心优势保持

RippleFlow设计的核心优势应继续强化：
1. **六阶段流水线**: 设计精妙，保持模块化
2. **敏感内容保护**: 机制完整，是企业级必备
3. **当事人修正**: 保证知识准确性，形成闭环
4. **AI管家概念**: 差异化竞争点，持续投入

### 9.2 关键改进方向

1. **成本控制**: LLM调用成本是长期运营关键，必须优化
2. **性能保障**: 提前规划数据增长，避免性能瓶颈
3. **用户体验**: 从"能用"到"好用"，细节打磨
4. **可观测性**: 运维友好度是团队自用工具的重要考量

### 9.3 风险提醒

⚠️ **高风险**:
- PostgreSQL在大数据量下的性能风险
- LLM API稳定性对系统的影响
- 敏感内容误判的法律责任

⚠️ **中风险**:
- 用户不使用（需要培养使用习惯）
- 知识质量参差不齐
- 团队成员抵触AI介入

⚠️ **建议缓解措施**:
- 提前做性能压测
- 增加LLM降级和熔断机制
- 建立人工审核流程
- 加强产品推广和培训

---

**评审完成时间**: 2026-03-02  
**评审人**: Kimi (AI Product Architect)  
**建议有效期**: 6个月（随产品迭代更新）

---

## 十二、信息域（Domain）架构设计建议

### 12.1 问题背景

**业务场景**：一个团队可能建立多个群组，这些群组之间存在不同的关联关系：
- **独立群组**：如私密小组、临时讨论组，信息应完全隔离
- **关联群组**：如产品群+技术群+测试群，信息需要部分共享
- **跨域协作**：如产品域的待办需要技术域的人员处理

**当前架构的局限**：
- 所有群组共享统一的知识库，缺乏逻辑隔离
- 无法区分哪些信息应该跨群流动（如待办任务）
- 缺乏对群组关联关系的显式建模

### 12.2 三层实现方案

基于现有架构的分层演进策略：

#### Phase 1: 虚拟域（标签层）—— 低复杂度

利用现有 `chat_rooms.metadata` JSONB 字段实现轻量级域标识：

```sql
-- 新增域定义表（可选，简单场景可省略）
CREATE TABLE domains (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(100) NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- 在现有 chat_rooms 表增加域关联
ALTER TABLE chat_rooms ADD COLUMN domain_id UUID REFERENCES domains(id);

-- 查询时按域过滤（NULL 表示公共群）
WHERE domain_id = 'xxx' OR domain_id IS NULL
```

**核心逻辑**：
- 群组归属于特定域，NULL 表示跨域公共群
- 知识库查询增加 `domain_id` 过滤条件
- 利用现有 `threads.primary_room_id → chat_rooms` 关联链实现域隔离

**实现复杂度**：⭐⭐（修改范围小，无破坏性变更）

#### Phase 2: 跨域信息流规则 —— 中等复杂度

针对需要跨域流动的信息（如待办任务），增加可见性控制：

```sql
-- 待办表增加可见性范围
ALTER TABLE todos ADD COLUMN visibility_scope VARCHAR(50) 
  DEFAULT 'domain' 
  CHECK (visibility_scope IN ('private', 'domain', 'cross_domain', 'public'));

-- 新增跨域授权表（记录哪些域可以访问本域信息）
CREATE TABLE domain_sharing_rules (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_domain_id UUID NOT NULL REFERENCES domains(id),
    target_domain_id UUID NOT NULL REFERENCES domains(id),
    info_type       VARCHAR(50) NOT NULL,  -- 'todo', 'thread', 'reference'
    allowed         BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(source_domain_id, target_domain_id, info_type)
);
```

**信息流规则建议**：

| 信息类型 | 默认可见性 | 跨域策略 |
|----------|------------|----------|
| **个人待办** | private | 仅自己可见 |
| **团队待办** | domain | 同域成员可见 |
| **跨域待办** | cross_domain | 显式指定目标域 |
| **技术决策** | domain | 可配置为公开 |
| **参考数据** | public | 所有域可见 |

**跨域待办示例**：
```
@张三（产品域）请提供API文档
@李四（技术域）负责开发实现
cross_domain: ["产品域", "技术域"]
```

**实现复杂度**：⭐⭐⭐⭐（需要设计规则引擎和权限检查）

#### Phase 3: 知识库域隔离 —— 低复杂度（利用现有架构）

知识图谱天然支持域过滤，无需重构：

```sql
-- 查询某域知识的 SQL（利用现有关联链）
SELECT kn.* FROM knowledge_nodes kn
JOIN threads t ON t.id = (kn.attributes->>'thread_id')::UUID
JOIN chat_rooms cr ON cr.id = t.primary_room_id
WHERE cr.domain_id = '目标域ID';

-- 或从 graph_nodes 直接过滤
SELECT * FROM knowledge_nodes
WHERE attributes->>'domain_id' = 'xxx';
```

**架构优势**：
- 现有 `knowledge_nodes.attributes` JSONB 字段可直接存储 `domain_id`
- `threads` 已关联 `primary_room_id → chat_rooms`
- 域过滤只需增加 WHERE 条件，不影响核心架构

**实现复杂度**：⭐⭐（查询层修改，无表结构变更）

### 12.3 复杂度评估矩阵

| 功能模块 | 技术复杂度 | 业务复杂度 | 建议阶段 | 预估工作量 |
|----------|------------|------------|----------|------------|
| **域标签管理** | 低（新增字段） | 低（管理员配置） | Phase 1 | 2天 |
| **域内知识检索** | 低（JOIN过滤） | 低（自动过滤） | Phase 1 | 1天 |
| **域可见性UI** | 中（前端适配） | 中（用户理解） | Phase 1 | 3天 |
| **跨域待办同步** | 中（规则引擎） | 高（边界模糊） | Phase 2 | 5天 |
| **跨域权限控制** | 高（ACL模型） | 高（管理员负担） | 暂缓 | - |
| **域间关联图谱** | 中（图查询） | 中（可视化） | Phase 3 | 3天 |

### 12.4 推荐起步方案（最小可行产品）

**建议优先实施 Phase 1**：

1. **数据库变更**：
   ```sql
   -- 仅新增一个字段
   ALTER TABLE chat_rooms ADD COLUMN domain_id UUID;
   CREATE INDEX idx_rooms_domain ON chat_rooms(domain_id);
   ```

2. **API调整**：
   ```yaml
   # 查询参数增加域过滤
   GET /api/v1/threads?domain_id=xxx&include_public=true
   GET /api/v1/search?q=redis&domain_id=xxx
   ```

3. **UI适配**：
   - 群组设置页面增加"所属域"下拉选择
   - 搜索界面增加"当前域/全部"切换
   - 知识库浏览按域分组显示

4. **暂不处理**：
   - 跨域待办流动（保持现有"公共"性质）
   - 复杂权限控制（使用简单规则：同域可见）
   - 域间数据同步（手动处理）

### 12.5 待决策问题

1. **域边界定义**：是按组织架构（部门）划分，还是按项目/产品划分？
2. **跨域待办策略**：是否需要类似邮件抄送的"@domain"语法？
3. **知识继承规则**：公共群的知识是否自动对所有域可见？
4. **域管理员权限**：是否需要独立的域级管理员角色？

### 12.6 实施建议

**短期（1-2周）**：
- 完成 Phase 1 的域标签功能
- 在测试环境验证域隔离效果
- 收集用户反馈

**中期（1-2月）**：
- 根据实际使用场景评估是否需要 Phase 2
- 优先实现高频跨域场景（如待办指派）

**长期（按需）**：
- 考虑是否需要完整的域权限体系
- 评估引入 RBAC 或 ABAC 模型的必要性

### 12.7 历史数据导入与信息链重建（边界场景）

#### 12.7.1 场景描述

当新群组被纳入信息域时，需要导入该群的历史消息数据，这会产生以下复杂情况：

**场景A：补充历史上下文**
```
时间线：
T1: 产品群讨论"支付功能设计"（已归档为线索A）
T2: 技术群讨论"支付接口实现"（已归档为线索B）
T3: 现在将技术群纳入产品域

问题：
- 线索A和线索B实际上是同一话题的不同视角
- 需要建立跨群关联，形成完整信息链
- 可能需要合并线索或建立父子关系
```

**场景B：信息冲突与修正**
```
已有知识：线索A状态为"讨论中"（基于产品群消息）
新导入历史：技术群3天前已决定"使用方案X"

问题：
- 知识节点状态需要从"讨论中"更新为"已决策"
- 需要追溯更新相关待办、决策记录
- 可能影响依赖该知识的其他线索
```

**场景C：时间线插入**
```
域内现有消息：2024-01-15 至 2024-03-01
新群历史消息：2023-12-01 至 2024-02-15

问题：
- 新消息时间戳早于部分现有知识节点
- 需要在知识图谱中正确排序和关联
- 可能影响热度计算、趋势分析
```

#### 12.7.2 技术挑战

| 挑战 | 影响 | 复杂度 |
|------|------|--------|
| **线索合并检测** | 需要识别跨群相关话题 | ⭐⭐⭐⭐ |
| **知识状态回溯** | 更新已有节点的状态和属性 | ⭐⭐⭐ |
| **关联关系重建** | 重新计算实体间的关系边 | ⭐⭐⭐⭐ |
| **时间线重排** | 影响时序分析和趋势计算 | ⭐⭐ |
| **LLM重新分析** | 历史消息需要重新提取结构化信息 | ⭐⭐⭐⭐⭐ |
| **数据一致性** | 确保更新后知识图谱逻辑自洽 | ⭐⭐⭐⭐ |

#### 12.7.3 解决方案建议

**方案1：增量式历史导入（推荐）**

```sql
-- 1. 创建历史导入任务表
CREATE TABLE domain_import_tasks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    domain_id       UUID NOT NULL REFERENCES domains(id),
    room_id         UUID NOT NULL REFERENCES chat_rooms(id),
    import_status   VARCHAR(50) DEFAULT 'pending',
    message_count   INTEGER,
    processed_count INTEGER DEFAULT 0,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    conflicts_found INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 冲突检测记录
CREATE TABLE import_conflicts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id         UUID REFERENCES domain_import_tasks(id),
    conflict_type   VARCHAR(50),  -- 'duplicate_thread', 'status_mismatch', 'entity_collision'
    existing_node_id UUID REFERENCES knowledge_nodes(id),
    new_evidence    JSONB,
    resolution      VARCHAR(50),  -- 'merged', 'separated', 'updated', 'pending_review'
    resolved_by     VARCHAR(255),
    resolved_at     TIMESTAMPTZ
);
```

**处理流程**：
```
1. 标记导入模式
   └─ chat_rooms.import_mode = 'historical_backfill'
   
2. 批量处理历史消息（按时间倒序）
   ├─ 每100条为一个批次
   ├─ 运行标准6阶段流水线
   └─ 标记 message.processing_status = 'historical'
   
3. 冲突检测
   ├─ 相似主题检测（向量相似度 > 0.85）
   ├─ 实体冲突检测（同实体不同属性）
   ├─ 时间线冲突检测（因果倒置）
   └─ 记录到 import_conflicts
   
4. 自动/人工解决
   ├─ 高置信度冲突：自动合并
   ├─ 中置信度冲突：提示管理员
   └─ 低置信度冲突：作为独立线索保留
   
5. 知识图谱更新
   ├─ 更新相关节点时间戳范围
   ├─ 重新计算关系权重
   ├─ 刷新聚合统计（热度、趋势）
   └─ 触发依赖线索的级联更新
   
6. 完成标记
   └─ chat_rooms.import_mode = NULL
```

**方案2：只读历史快照（轻量级）**

如果完整重建过于复杂，可采用简化方案：

```sql
-- 历史数据仅做索引，不重建知识链
ALTER TABLE messages ADD COLUMN is_historical BOOLEAN DEFAULT false;

-- 历史消息可搜索，但不参与：
-- - 状态追踪（不更新待办状态）
-- - 决策追溯（仅作为参考）
-- - 知识图谱更新（不创建新节点）
-- 但保留：
-- - 全文检索
-- - 时间线浏览
-- - 人员提及关系
```

**方案3：领域专属重建（分域策略）**

不同域采用不同策略：

| 域类型 | 历史导入策略 | 理由 |
|--------|--------------|------|
| **核心域**（产品/技术） | 完整重建 | 知识准确性要求高 |
| **临时域**（项目组） | 只读快照 | 生命周期短，无需深度关联 |
| **跨域公共群** | 不导入历史 | 信息已分散在各域 |

#### 12.7.4 关键实现细节

**1. 线索合并算法**

```python
# 基于语义相似度的线索合并检测
def detect_merge_candidates(new_thread, domain_threads):
    candidates = []
    for existing in domain_threads:
        # 计算标题相似度
        title_sim = semantic_similarity(
            new_thread.title, 
            existing.title
        )
        
        # 计算实体重叠度
        common_entities = set(new_thread.entities) & set(existing.entities)
        entity_overlap = len(common_entities) / max(len(new_thread.entities), len(existing.entities))
        
        # 时间邻近度（30天内）
        time_proximity = 1 if abs(new_thread.date - existing.date) < 30 else 0.5
        
        # 综合评分
        score = (title_sim * 0.5 + entity_overlap * 0.3 + time_proximity * 0.2)
        
        if score > 0.75:
            candidates.append((existing, score))
    
    return sorted(candidates, key=lambda x: x[1], reverse=True)
```

**2. 知识状态更新策略**

```
原则：新证据优先级高于旧证据

场景：已有状态 vs 新证据
├─ "讨论中" + "已决策" → 更新为"已决策"
├─ "待确认" + "已拒绝" → 更新为"已拒绝"  
├─ "进行中" + "已完成" → 更新为"已完成"
└─ "已归档" + "新讨论" → 拆分为新线索，建立关联

特殊情况：
- 若新证据时间戳早于已有证据，需提示人工审核
- 若状态变更涉及敏感内容，重新触发授权流程
```

**3. 级联更新范围**

```sql
-- 当节点状态变更时，需要级联更新的对象
WITH RECURSIVE impact_chain AS (
    -- 直接关联的线索
    SELECT 
        source_id as node_id,
        target_id as related_id,
        edge_type,
        1 as depth
    FROM knowledge_edges
    WHERE source_id = '变更节点ID'
    
    UNION ALL
    
    -- 间接关联（最多3层）
    SELECT 
        ic.node_id,
        ke.target_id,
        ke.edge_type,
        ic.depth + 1
    FROM impact_chain ic
    JOIN knowledge_edges ke ON ic.related_id = ke.source_id
    WHERE ic.depth < 3
)
-- 需要更新的对象：
-- 1. 依赖该节点的待办任务
-- 2. 引用该节点的决策记录
-- 3. 关联的话题线索状态
-- 4. 知识图谱聚合统计
```

#### 12.7.5 复杂度评估

| 子功能 | 技术复杂度 | 业务影响 | 建议策略 |
|--------|------------|----------|----------|
| **历史消息批量处理** | ⭐⭐⭐ | 中 | 异步队列处理 |
| **相似线索检测** | ⭐⭐⭐⭐ | 高 | 结合规则+语义相似度 |
| **冲突自动解决** | ⭐⭐⭐⭐⭐ | 高 | 高置信度自动，低置信度人工 |
| **知识状态回溯** | ⭐⭐⭐ | 高 | 严格时序验证 |
| **级联更新** | ⭐⭐⭐⭐ | 中 | 限制影响范围（3层以内） |
| **导入任务管理** | ⭐⭐ | 低 | 标准任务队列 |

#### 12.7.6 实施建议

**Phase 1：基础导入（MVP）**
- 实现历史消息批量导入
- 仅创建新线索，不做合并检测
- 历史消息标记为 `is_historical = true`
- 可搜索但不影响现有知识状态
- 工作量：3-5天

**Phase 2：智能合并**
- 实现相似线索检测算法
- 提示管理员确认合并建议
- 支持手动关联已有线索
- 工作量：1周

**Phase 3：全自动重建**
- 高置信度冲突自动解决
- 知识状态自动回溯更新
- 完整的级联更新机制
- 工作量：2周

**风险控制**：
- 导入前创建知识图谱快照（备份）
- 支持按群撤销导入操作
- 导入过程中暂停该域的写操作
- 导入完成后发送变更摘要给域管理员

---

**评审完成时间**: 2026-03-02  
**评审人**: Kimi (AI Product Architect)  
**建议有效期**: 6个月（随产品迭代更新）
