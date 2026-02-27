#!/usr/bin/env python3
"""
恢复 Pixiv 标签数据库脚本

由于本地数据库丢失，本脚本通过 tags.json 重新导入已翻译和审核过的数据。
"""

import json
import logging
import os
import sqlite3
import sys
from datetime import datetime

# 确保可以导入 src 目录下的模块
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from dotenv import load_dotenv
from src.sqlite_storage import SQLiteStorage

load_dotenv()

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def main():
    json_path = "data/tags.json"
    db_path = os.getenv("SQLITE_DB_PATH", "data/pixiv_tags.db")

    # 检查数据库所在的文件夹是否存在
    db_dir = os.path.dirname(db_path)
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir)

    if not os.path.exists(json_path):
        logger.error(f"JSON 文件不存在: {json_path}")
        return 1

    logger.info(f"正在从 {json_path} 加载标签数据...")
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        logger.error(f"加载 JSON 失败: {e}")
        return 1

    tags = data.get("tags", {})
    if not tags:
        logger.warning("JSON 中没有找到标签数据")
        return 1

    logger.info(f"找到 {len(tags)} 个已标注的翻译，准备导入...")

    storage = SQLiteStorage(db_path)
    storage.init()  # 确保表、索引和 FTS 触发器已初始化

    count = 0
    with storage._get_connection() as conn:
        cursor = conn.cursor()
        for name, translation in tags.items():
            # 导入策略:
            # 1. 如果标签不存在则插入，赋予翻译并标记为已审核
            # 2. 如果标签已存在（例如重新爬取导致的），则覆盖其翻译并标记为已审核
            # 3. 初始频率可以设置为 1，也可以保持默认 0 (如果它之前不在)
            try:
                cursor.execute(
                    """
                    INSERT INTO pixiv_tags (name, chinese_translation, chinese_reviewed, updated_at)
                    VALUES (?, ?, 1, CURRENT_TIMESTAMP)
                    ON CONFLICT(name) DO UPDATE SET
                        chinese_translation = excluded.chinese_translation,
                        chinese_reviewed = 1,
                        updated_at = CURRENT_TIMESTAMP
                """,
                    (name, translation),
                )
                count += 1
            except sqlite3.Error as e:
                logger.error(f"导入标签 {name} 时出错: {e}")

            if count % 500 == 0:
                conn.commit()
                logger.info(f"已处理 {count} 个标签...")

        conn.commit()

        # 强制重建 FTS 索引
        logger.info("正在重建全文搜索索引...")
        conn.execute("INSERT INTO pixiv_tags_fts(pixiv_tags_fts) VALUES('rebuild')")
        conn.commit()

    logger.info(f"成功完成恢复！已恢复 {count} 个已审核的翻译。")
    logger.info(f"数据库文件路径: {os.path.abspath(db_path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
