-- ============================================================
-- fintech_system 知识图谱扩展
-- 在现有 fintech_db 上执行
-- ============================================================

-- 1. 节点注册表（统一管理所有节点）
CREATE TABLE IF NOT EXISTS kg_nodes (
    node_id     VARCHAR PRIMARY KEY,  -- 'macro.fed_rate' / 'company.600893' / 'industry.航空发动机'
    node_type   VARCHAR NOT NULL,     -- 'macro' / 'company' / 'industry' / 'policy' / 'commodity'
    label       VARCHAR NOT NULL,     -- 显示名 '美联储利率' / '航发动力'
    ts_code     VARCHAR,              -- 对应Tushare代码（公司节点专用）
    sw_l1       VARCHAR,              -- 申万一级行业
    sw_l2       VARCHAR,              -- 申万二级行业
    sw_l3       VARCHAR,              -- 申万三级行业
    meta        JSONB,                -- 其他扩展属性
    created_at  TIMESTAMP DEFAULT NOW(),
    updated_at  TIMESTAMP DEFAULT NOW()
);

-- 2. 因果边表（核心）
CREATE TABLE IF NOT EXISTS causal_edges (
    id          SERIAL PRIMARY KEY,
    from_node   VARCHAR NOT NULL REFERENCES kg_nodes(node_id),
    to_node     VARCHAR NOT NULL REFERENCES kg_nodes(node_id),
    relation    VARCHAR NOT NULL,     -- 'cost_driver'/'policy_impact'/'upstream'/'downstream'/'macro_driver'
    direction   SMALLINT NOT NULL,    -- +1 正向 / -1 反向
    lag_days    INTEGER,              -- 传导时滞（天）
    elasticity  FLOAT,                -- 回归系数（量化后填入）
    condition   TEXT,                 -- 触发条件 '仅当油价>$130时成立'
    evidence    TEXT,                 -- 来源 '601021 2025年报 p.42'
    confidence  FLOAT DEFAULT 0.5,   -- 置信度 0-1（初始0.5，回归验证后更新）
    is_verified BOOLEAN DEFAULT FALSE,-- 是否经过量化验证
    created_at  TIMESTAMP DEFAULT NOW(),
    updated_at  TIMESTAMP DEFAULT NOW(),
    UNIQUE(from_node, to_node, relation)
);

-- 3. 宏观时序表
CREATE TABLE IF NOT EXISTS macro_indicators (
    id          SERIAL PRIMARY KEY,
    indicator   VARCHAR NOT NULL,     -- 'PMI' / 'CPI' / 'USDCNY' / 'JET_FUEL'
    date        DATE NOT NULL,
    value       FLOAT NOT NULL,
    unit        VARCHAR,              -- '%' / 'CNY' / 'USD/barrel'
    source      VARCHAR,              -- 'NBS' / 'WIND' / 'EIA'
    created_at  TIMESTAMP DEFAULT NOW(),
    UNIQUE(indicator, date)
);

-- 4. 叙事层（Obsidian的结构化镜像）
CREATE TABLE IF NOT EXISTS narrative_nodes (
    id          SERIAL PRIMARY KEY,
    node_id     VARCHAR REFERENCES kg_nodes(node_id),
    date        DATE NOT NULL,
    thesis      TEXT,                 -- 核心判断
    reasoning   TEXT,                 -- 推理过程
    risks       TEXT,                 -- 风险点
    obsidian_path VARCHAR,            -- 对应Obsidian文件路径
    created_at  TIMESTAMP DEFAULT NOW()
);

-- ============================================================
-- 索引
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_causal_from ON causal_edges(from_node);
CREATE INDEX IF NOT EXISTS idx_causal_to ON causal_edges(to_node);
CREATE INDEX IF NOT EXISTS idx_causal_relation ON causal_edges(relation);
CREATE INDEX IF NOT EXISTS idx_macro_indicator_date ON macro_indicators(indicator, date);
CREATE INDEX IF NOT EXISTS idx_kg_nodes_type ON kg_nodes(node_type);
CREATE INDEX IF NOT EXISTS idx_kg_nodes_tscode ON kg_nodes(ts_code);

-- ============================================================
-- 种子数据：你当前持仓和核心关注节点
-- ============================================================
INSERT INTO kg_nodes (node_id, node_type, label, ts_code, sw_l1, sw_l2, sw_l3) VALUES
    ('company.600893', 'company', '航发动力', '600893.SH', '国防军工', '航空装备', '航空发动机'),
    ('company.601021', 'company', '春秋航空', '601021.SH', '交通运输', '航空运输', '航空运输'),
    ('company.DIDIY',  'company', '滴滴出行', 'DIDIY',     '信息技术', '互联网', '出行平台'),
    ('macro.fed_rate',  'macro',   '美联储利率',  NULL, NULL, NULL, NULL),
    ('macro.usdcny',    'macro',   '美元人民币汇率', NULL, NULL, NULL, NULL),
    ('macro.jet_fuel',  'commodity','航空煤油价格', NULL, NULL, NULL, NULL),
    ('macro.oil_wti',   'commodity','WTI原油',    NULL, NULL, NULL, NULL),
    ('macro.pmi_mfg',   'macro',   'PMI制造业',   NULL, NULL, NULL, NULL),
    ('policy.15th_5year','policy', '十五五规划',   NULL, NULL, NULL, NULL),
    ('policy.low_alt',  'policy',  '低空经济政策', NULL, NULL, NULL, NULL),
    ('policy.caac_cert','policy',  'CAAC适航认证', NULL, NULL, NULL, NULL),
    ('company.yingliu', 'company', '应流股份',  '603308.SH', '国防军工', '航空装备', '航空发动机'),
    ('company.tunan',   'company', '图南股份',  '300855.SZ', '国防军工', '航空装备', '航空发动机'),
    ('entity.tonghang', 'company', '通航动力公司', NULL, '工业', '通用航空', '通用航空发动机')
ON CONFLICT (node_id) DO NOTHING;

-- 种子边：已经压测过的因果关系
INSERT INTO causal_edges (from_node, to_node, relation, direction, lag_days, condition, evidence, confidence, is_verified) VALUES
    ('macro.oil_wti',  'macro.jet_fuel',   'price_transmission', +1, 7,   NULL, 'EIA历史数据',        0.95, TRUE),
    ('macro.jet_fuel', 'company.601021',   'cost_driver',        -1, 30,  NULL, '601021 2025年报 成本结构', 0.90, TRUE),
    ('macro.fed_rate', 'macro.usdcny',     'macro_driver',       +1, 90,  NULL, '2022-2023联储加息周期', 0.75, TRUE),
    ('macro.usdcny',   'company.600893',   'cost_driver',        +1, 60,  '进口原材料占比>30%', '600893 2025年报 采购模式', 0.65, FALSE),
    ('policy.caac_cert','company.600893',  'policy_impact',      +1, 180, 'CJ-1000A认证通过', '市场一致预期2027-2028', 0.70, FALSE),
    ('policy.low_alt', 'entity.tonghang',  'policy_impact',      +1, 365, NULL, '通航动力临港基地投运', 0.60, FALSE),
    ('entity.tonghang','company.600893',   'equity_value',       +1, 730, '商业化订单落地', '600893持股26.59%', 0.55, FALSE),
    ('company.yingliu','company.600893',   'upstream',           +1, 90,  NULL, '供应商关系', 0.85, TRUE),
    ('company.tunan',  'company.600893',   'upstream',           +1, 90,  NULL, '供应商关系', 0.85, TRUE)
ON CONFLICT (from_node, to_node, relation) DO NOTHING;

