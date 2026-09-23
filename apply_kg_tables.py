"""
fintech_system 知识图谱表初始化脚本
在本地机器执行：python apply_kg_tables.py
"""
from sqlalchemy import create_engine, text

DB_URL = "postgresql://fintech_user:fintech_pass@localhost:5432/fintech_db"

def apply():
    engine = create_engine(DB_URL)
    with open("add_knowledge_graph_tables.sql", "r") as f:
        sql = f.read()

    with engine.connect() as conn:
        # 按语句分割执行
        statements = [s.strip() for s in sql.split(";") if s.strip() and not s.strip().startswith("--")]
        for stmt in statements:
            try:
                conn.execute(text(stmt))
            except Exception as e:
                print(f"⚠️  跳过: {str(e)[:80]}")
        conn.commit()
    print("✅ 知识图谱表初始化完成")

def verify():
    engine = create_engine(DB_URL)
    with engine.connect() as conn:
        tables = ["kg_nodes", "causal_edges", "macro_indicators", "narrative_nodes"]
        for t in tables:
            r = conn.execute(text(f"SELECT COUNT(*) FROM {t}")).scalar()
            print(f"  {t}: {r} 行")

        print("\n--- 种子因果链（置信度>0.8）---")
        rows = conn.execute(text("""
            SELECT
                fn.label || ' → ' || tn.label AS path,
                e.relation,
                e.direction,
                e.lag_days,
                e.confidence,
                e.is_verified
            FROM causal_edges e
            JOIN kg_nodes fn ON e.from_node = fn.node_id
            JOIN kg_nodes tn ON e.to_node   = tn.node_id
            WHERE e.confidence >= 0.8
            ORDER BY e.confidence DESC
        """)).fetchall()
        for r in rows:
            verified = "✅" if r.is_verified else "⬜"
            direction = "↑" if r.direction == 1 else "↓"
            lag = f"时滞{r.lag_days}天" if r.lag_days else ""
            print(f"  {verified} {r.path} [{r.relation}] {direction} {lag} conf={r.confidence}")

if __name__ == "__main__":
    apply()
    verify()
