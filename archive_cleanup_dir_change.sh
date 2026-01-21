#!/bin/bash
###############################################################################
# Tibero Archive Log Cleanup Script (Primary Only) - Sanitized for Public Repo
###############################################################################

set -euo pipefail

# ----------------------------
# cron 환경 설정
# ----------------------------
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/bash

# ----------------------------
# 환경 설정 (Sanitized)
# ----------------------------
TARGET_DIR="/path/to/archivelog"                  
DAYS=14                                           # 삭제 기준 (2주)
DRY_RUN=false                                     # true: 삭제 미수행
SLEEP_SEC=0.1                                     # 삭제 속도 제한

TARGET_LOG_DIR="/path/to/archive_cleanup_log/target"  
RESULT_LOG_DIR="/path/to/archive_cleanup_log/result"  
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

TARGET_LOG="${TARGET_LOG_DIR}/target_${DATE}.log"
RESULT_LOG="${RESULT_LOG_DIR}/result_${DATE}.log"

mkdir -p "$TARGET_LOG_DIR" "$RESULT_LOG_DIR"

# ----------------------------
# 사전 체크 (아카이브 디렉토리)
# ----------------------------
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "[ERROR] TARGET_DIR not found: $TARGET_DIR" >> "$RESULT_LOG"
    exit 1
fi

# ----------------------------
# Tibero Primary 여부 체크
# ----------------------------
TB_PROCESS=$(ps -ef | grep -w tbsvr | grep -v grep || true)

if [[ -z "$TB_PROCESS" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Tibero tbsvr process not running" >> "$RESULT_LOG"
    exit 1
fi

# PRIMARY (NORMAL) 여부 확인
if echo "$TB_PROCESS" | grep -q -- "-t NORMAL"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK] Tibero PRIMARY(NORMAL) detected. Archive cleanup allowed." >> "$RESULT_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK] tbsvr process detected." >> "$RESULT_LOG"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Tibero is NOT PRIMARY(NORMAL). Skip archive cleanup." >> "$RESULT_LOG"
    exit 0
fi

# ----------------------------
# 시작 로그
# ----------------------------
{
    echo "============================================================"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Start Tibero archive cleanup"
    echo "TARGET_DIR : $TARGET_DIR"
    echo "DELETE AGE : ${DAYS} days"
    echo "DRY_RUN    : $DRY_RUN"
} >> "$RESULT_LOG"

# ----------------------------
# 삭제 전 용량
# ----------------------------
ARCHIVE_SIZE_BEFORE=$(du -sh "$TARGET_DIR" 2>/dev/null | awk '{print $1}' || echo "N/A")
echo "Archive directory size before deletion: $ARCHIVE_SIZE_BEFORE" >> "$RESULT_LOG"

# ----------------------------
# 삭제 대상 파일 수집
# ----------------------------
find "$TARGET_DIR" -type f -name "*.arc" -mtime +"$DAYS" 2>/dev/null > "$TARGET_LOG" || true

if [[ ! -s "$TARGET_LOG" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No files to delete" >> "$RESULT_LOG"
    exit 0
fi

# ----------------------------
# 삭제 수행
# ----------------------------
SUCCESS=0
FAIL=0

echo "[archive log delete] start" >> "$RESULT_LOG"

while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $FILE" >> "$RESULT_LOG"
        SUCCESS=$((SUCCESS+1))
    else
        if ionice -c2 -n7 nice -n 19 rm -f -- "$FILE"; then
            echo "[OK]   $FILE" >> "$RESULT_LOG"
            SUCCESS=$((SUCCESS+1))
        else
            echo "[FAIL] $FILE" >> "$RESULT_LOG"
            FAIL=$((FAIL+1))
        fi
        sleep "$SLEEP_SEC"
    fi
done < "$TARGET_LOG"

# ----------------------------
# 삭제 후 용량
# ----------------------------
ARCHIVE_SIZE_AFTER=$(du -sh "$TARGET_DIR" 2>/dev/null | awk '{print $1}' || echo "N/A")

# ----------------------------
# 결과 요약
# ----------------------------
TOTAL=$((SUCCESS+FAIL))
{
    echo "-------------------------------------------------------------"
    echo "Total   : $TOTAL"
    echo "Success : $SUCCESS"
    echo "Fail    : $FAIL"
    echo "Size before: $ARCHIVE_SIZE_BEFORE"
    echo "Size after : $ARCHIVE_SIZE_AFTER"
    echo "-------------------------------------------------------------"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] End"
} >> "$RESULT_LOG"
