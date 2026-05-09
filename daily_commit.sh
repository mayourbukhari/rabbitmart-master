#!/bin/bash
set -u

# Configuration
REPO_DIR="/Users/basitbukhari/Documents/rabbitmart-master"
LOG_DIR="$REPO_DIR/logs"
LOG_FILE="$LOG_DIR/daily_commit.log"
MAX_RETRIES=3
SLEEP_BASE=2   # base for exponential backoff (seconds)
# If you want email notifications on failure set EMAIL_ON_FAILURE=true and RECIPIENT_EMAIL
EMAIL_ON_FAILURE=false
RECIPIENT_EMAIL=""

mkdir -p "$LOG_DIR"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
log_info() { echo "[$(timestamp)] [INFO] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(timestamp)] [ERROR] $*" | tee -a "$LOG_FILE"; }

run_with_retries() {
	local -a cmd=("$@")
	local attempt=0
	while true; do
		attempt=$((attempt + 1))
		"${cmd[@]}" >>"$LOG_FILE" 2>&1 && return 0
		local rc=$?
		if [ $attempt -ge $MAX_RETRIES ]; then
			log_error "Command failed after $attempt attempts: ${cmd[*]} (rc=$rc)"
			return $rc
		fi
		local sleep_for=$((SLEEP_BASE ** attempt))
		log_info "Command failed (rc=$rc). Retry $attempt/${MAX_RETRIES} in ${sleep_for}s: ${cmd[*]}"
		sleep "$sleep_for"
	done
}

send_failure_email() {
	local subject="[TAHA EMPORIUM] daily_commit.sh failure on $(hostname)"
	local body="Daily commit script failed on $(hostname) at $(timestamp). See log: $LOG_FILE\n\nLast 200 lines:\n$(tail -n 200 "$LOG_FILE")"
	if [ "$EMAIL_ON_FAILURE" != true ] || [ -z "$RECIPIENT_EMAIL" ]; then
		log_info "EMAIL_ON_FAILURE not enabled or RECIPIENT_EMAIL not set; skipping email notification."
		return 0
	fi

	if command -v sendmail >/dev/null 2>&1; then
		{
			echo "To: $RECIPIENT_EMAIL"
			echo "Subject: $subject"
			echo ""
			echo "$body"
		} | sendmail -t
		log_info "Sent failure email to $RECIPIENT_EMAIL via sendmail"
		return 0
	fi

	if command -v mail >/dev/null 2>&1; then
		echo "$body" | mail -s "$subject" "$RECIPIENT_EMAIL"
		log_info "Sent failure email to $RECIPIENT_EMAIL via mail"
		return 0
	fi

	log_error "No mailer (sendmail or mail) available to send failure email to $RECIPIENT_EMAIL"
	return 1
}

# Start script
log_info "Starting daily_commit.sh"

if [ ! -d "$REPO_DIR" ]; then
	log_error "Repository directory does not exist: $REPO_DIR"
	send_failure_email || true
	exit 1
fi

cd "$REPO_DIR" || { log_error "Failed to cd to $REPO_DIR"; send_failure_email || true; exit 1; }

# Verify this is a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	log_error "Not a git repository: $REPO_DIR"
	send_failure_email || true
	exit 1
fi

# Make sure we have a known branch to push to. Default to main but let git determine current branch if available.
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
TARGET_BRANCH="main"

# Create an empty commit with a message including the current date
COMMIT_MSG="Daily commit $(date +'%Y-%m-%d %H:%M:%S')"
log_info "Creating empty commit on branch $CURRENT_BRANCH with message: $COMMIT_MSG"

if ! run_with_retries git commit --allow-empty -m "$COMMIT_MSG"; then
	log_error "git commit failed"
	send_failure_email || true
	exit 1
fi

# Push the commit to the configured remote (origin) and target branch
log_info "Pushing to origin $TARGET_BRANCH"
if ! run_with_retries git push origin "$TARGET_BRANCH"; then
	log_error "git push failed"
	send_failure_email || true
	exit 1
fi

log_info "daily_commit.sh completed successfully"
exit 0
