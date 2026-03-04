#!/bin/bash
# Script: dos_detector.sh
# Description: Detect potential DoS attacks by monitoring 429s, CPU, memory
# Run with: sudo ./dos_detector.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# CONFIGURATION - ADJUST THESE VALUES
# ============================================

# Thresholds
CPU_THRESHOLD=80              # Alert if CPU > 80%
MEMORY_THRESHOLD=80           # Alert if memory > 80%
LOAD_THRESHOLD=2.0            # Alert if load average > 2.0
RATE_LIMIT_THRESHOLD=50       # Alert if IP has > 50 rate-limited requests
TOTAL_429_THRESHOLD=200       # Alert if total 429s in last minute > 200

# Files
NGINX_ACCESS_LOG="/var/log/nginx/access.log"
NGINX_ERROR_LOG="/var/log/nginx/error.log"
DOS_LOG_FILE="/var/log/dos_detector.log"        # <-- CHANGED: DOS-specific log
DEPLOY_LOG_FILE="/home/pi/fractal_deploy.log"   # <-- Reference to deploy log (optional)

# Monitoring duration (seconds)
CHECK_INTERVAL=10
HISTORY_MINUTES=5

# ============================================
# INITIALIZATION
# ============================================

# Create log file if it doesn't exist
touch "$DOS_LOG_FILE"

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$DOS_LOG_FILE"
}

# Function to print colored output
print_status() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️ WARNING:${NC} $1"
    log_message "WARNING" "$1"
}

print_alert() {
    echo -e "${RED}[$(date '+%H:%M:%S')] 🚨 ALERT:${NC} $1"
    log_message "ALERT" "$1"
}

print_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $1"
}

# ============================================
# SYSTEM MONITORING FUNCTIONS
# ============================================

check_cpu_memory() {
    local alert_count=0
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    if [ -z "$cpu_usage" ]; then
        cpu_usage=$(top -bn1 | grep "%Cpu" | awk '{print $2}')
    fi
    
    # Memory usage
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100}')
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | tr -d ' ')
    
    # Display current stats
    echo -e "${CYAN}   CPU: ${cpu_usage}% | Memory: ${mem_usage}% | Load: ${load_avg}${NC}"
    
    # Check thresholds
    if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )); then
        print_alert "High CPU usage: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
        alert_count=$((alert_count + 1))
    fi
    
    if (( $(echo "$mem_usage > $MEMORY_THRESHOLD" | bc -l) )); then
        print_alert "High memory usage: ${mem_usage}% (threshold: ${MEMORY_THRESHOLD}%)"
        alert_count=$((alert_count + 1))
    fi
    
    if (( $(echo "$load_avg > $LOAD_THRESHOLD" | bc -l) )); then
        print_alert "High load average: ${load_avg} (threshold: ${LOAD_THRESHOLD})"
        alert_count=$((alert_count + 1))
    fi
    
    return $alert_count
}

# ============================================
# 429 RATE LIMIT MONITORING
# ============================================

check_rate_limited_ips() {
    local time_filter=$(date -d "$HISTORY_MINUTES minutes ago" '+%d/%b/%Y:%H:%M')
    
    if [ ! -f "$NGINX_ACCESS_LOG" ]; then
        echo -e "${YELLOW}   Nginx access log not found${NC}"
        return
    fi
    
    # Find IPs with many 429 responses
    local suspicious_ips=$(tail -10000 "$NGINX_ACCESS_LOG" | \
        awk -v time="$time_filter" '$4 > time && $9 == 429 {print $1}' | \
        sort | uniq -c | sort -nr | \
        awk -v threshold="$RATE_LIMIT_THRESHOLD" '$1 > threshold {print $2, $1}')
    
    if [ -n "$suspicious_ips" ]; then
        echo -e "${RED}   Suspicious IPs (rate limited):${NC}"
        echo "$suspicious_ips" | while read ip count; do
            print_alert "IP $ip has $count rate-limited requests in last $HISTORY_MINUTES minutes"
            
            # Show what they were trying to access
            echo -e "${YELLOW}      Top endpoints accessed by $ip:${NC}"
            tail -10000 "$NGINX_ACCESS_LOG" | grep "$ip" | grep " 429 " | \
                awk '{print $7}' | sort | uniq -c | sort -nr | head -3 | \
                while read req_count endpoint; do
                echo -e "         $req_count x $endpoint"
            done
        done
    else
        echo -e "${GREEN}   No suspicious rate-limited IPs detected${NC}"
    fi
    
    # Total 429 count
    local total_429=$(tail -10000 "$NGINX_ACCESS_LOG" | \
        awk -v time="$time_filter" '$4 > time && $9 == 429' | wc -l)
    
    echo -e "   Total 429 responses in last $HISTORY_MINUTES minutes: $total_429"
    
    if [ "$total_429" -gt "$TOTAL_429_THRESHOLD" ]; then
        print_alert "High volume of rate-limited requests: $total_429 (threshold: $TOTAL_429_THRESHOLD)"
    fi
}

# ============================================
# CONNECTION MONITORING
# ============================================

check_connections() {
    local total_connections=$(ss -tun | tail -n +2 | wc -l)
    local established=$(ss -tun state established | wc -l)
    local syn_recv=$(ss -n state syn-recv | wc -l)
    local time_wait=$(ss -n state time-wait | wc -l)
    
    echo -e "   Connections: Total: $total_connections | EST: $established | SYN: $syn_recv | TW: $time_wait"
    
    # Check for possible SYN flood
    if [ "$syn_recv" -gt 50 ]; then
        print_alert "Possible SYN flood: $syn_recv half-open connections"
        
        # Show top IPs with SYN_RECV
        echo -e "${YELLOW}   Top IPs in SYN_RECV state:${NC}"
        ss -n state syn-recv | awk 'NR>1 {print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -5
    fi
    
    # Check for many connections per IP
    local high_conn_ips=$(ss -tun | awk 'NR>1 {print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -5)
    echo "$high_conn_ips" | while read count ip; do
        if [ "$count" -gt 30 ]; then
            print_warning "IP $ip has $count connections"
        fi
    done
}

# ============================================
# TOP ATTACKER REPORT
# ============================================

show_top_attackers() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}📊 TOP POTENTIAL ATTACKERS (Last $HISTORY_MINUTES minutes)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    
    local time_filter=$(date -d "$HISTORY_MINUTES minutes ago" '+%d/%b/%Y:%H:%M')
    
    if [ ! -f "$NGINX_ACCESS_LOG" ]; then
        return
    fi
    
    # Top IPs by total requests
    echo -e "\n${YELLOW}By total requests:${NC}"
    tail -10000 "$NGINX_ACCESS_LOG" | \
        awk -v time="$time_filter" '$4 > time {print $1}' | \
        sort | uniq -c | sort -nr | head -10 | \
        while read count ip; do
        if [ "$count" -gt 100 ]; then
            echo -e "${RED}   $ip: $count requests (HIGH)${NC}"
        else
            echo -e "   $ip: $count requests"
        fi
    done
    
    # Top IPs by 429 responses (rate limited)
    echo -e "\n${YELLOW}By rate-limited requests (429):${NC}"
    tail -10000 "$NGINX_ACCESS_LOG" | \
        awk -v time="$time_filter" '$4 > time && $9 == 429 {print $1}' | \
        sort | uniq -c | sort -nr | head -10 | \
        while read count ip; do
        if [ "$count" -gt "$RATE_LIMIT_THRESHOLD" ]; then
            echo -e "${RED}   $ip: $count x 429 (SUSPICIOUS)${NC}"
        elif [ "$count" -gt 10 ]; then
            echo -e "${YELLOW}   $ip: $count x 429${NC}"
        else
            echo -e "   $ip: $count x 429"
        fi
    done
    
    # Top IPs by 5xx errors (server errors)
    echo -e "\n${YELLOW}By server errors (5xx):${NC}"
    tail -10000 "$NGINX_ACCESS_LOG" | \
        awk -v time="$time_filter" '$4 > time && $9 ~ /^5[0-9][0-9]/ {print $1}' | \
        sort | uniq -c | sort -nr | head -5
}

# ============================================
# QUICK ACTIONS MENU
# ============================================

show_actions() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}🛠️  QUICK ACTIONS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo "   b) Block an IP with iptables"
    echo "   u) Unblock an IP"
    echo "   r) Show recent alerts"
    echo "   l) View rate limit stats"
    echo "   d) View deployment log"
    echo "   c) Clear screen"
    echo "   q) Quit monitoring"
    echo -n -e "${YELLOW}Action (b/u/r/l/d/c/q): ${NC}"
}

block_ip() {
    echo -n -e "Enter IP to block: "
    read ip
    if [ -n "$ip" ]; then
        iptables -A INPUT -s "$ip" -j DROP
        iptables -A INPUT -s "$ip" -m limit --limit 1/s -j LOG --log-prefix "BLOCKED: "
        print_alert "Blocked IP: $ip"
        echo "$(date) - Blocked $ip" >> "$DOS_LOG_FILE"
    fi
}

unblock_ip() {
    echo -n -e "Enter IP to unblock: "
    read ip
    if [ -n "$ip" ]; then
        iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
        print_success "Unblocked IP: $ip"
        echo "$(date) - Unblocked $ip" >> "$DOS_LOG_FILE"
    fi
}

show_recent_alerts() {
    echo -e "\n${YELLOW}Recent Alerts (last 20):${NC}"
    tail -20 "$DOS_LOG_FILE" | while read line; do
        if [[ "$line" == *"ALERT"* ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ "$line" == *"WARNING"* ]]; then
            echo -e "${YELLOW}$line${NC}"
        else
            echo "$line"
        fi
    done
}

show_deploy_log() {
    if [ -f "$DEPLOY_LOG_FILE" ]; then
        echo -e "\n${BLUE}Last 10 lines of deployment log:${NC}"
        tail -10 "$DEPLOY_LOG_FILE"
    else
        echo -e "${YELLOW}Deployment log not found: $DEPLOY_LOG_FILE${NC}"
    fi
}

show_rate_limit_stats() {
    echo -e "\n${BLUE}Rate Limit Statistics:${NC}"
    
    # Rate limit zone status
    echo -e "\n${YELLOW}Nginx rate limit zones:${NC}"
    nginx -T 2>/dev/null | grep -A 2 "limit_req_zone"
    
    # Current rate limit effectiveness
    if [ -f "$NGINX_ACCESS_LOG" ]; then
        echo -e "\n${YELLOW}Rate limit effectiveness (last 5 minutes):${NC}"
        local time_filter=$(date -d '5 minutes ago' '+%d/%b/%Y:%H:%M')
        local total_req=$(tail -10000 "$NGINX_ACCESS_LOG" | awk -v time="$time_filter" '$4 > time' | wc -l)
        local rate_limited=$(tail -10000 "$NGINX_ACCESS_LOG" | awk -v time="$time_filter" '$4 > time && $9 == 429' | wc -l)
        
        if [ "$total_req" -gt 0 ]; then
            local percentage=$(echo "scale=2; $rate_limited * 100 / $total_req" | bc)
            echo "   Total requests: $total_req"
            echo "   Rate limited: $rate_limited ($percentage%)"
        fi
    fi
}

# ============================================
# MAIN MONITORING LOOP
# ============================================

main() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   DoS Attack Detection Script${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Monitoring started at $(date)"
    echo -e "DOS Log file: $DOS_LOG_FILE"
    echo -e "Deploy Log file: $DEPLOY_LOG_FILE"
    echo -e "Check interval: ${CHECK_INTERVAL}s"
    echo -e "Analysis window: ${HISTORY_MINUTES} minutes"
    echo -e "${YELLOW}Press 'm' for menu or Ctrl+C to stop${NC}"
    echo ""
    
    local iteration=0
    
    # Set up non-blocking input
    stty -echo -icanon time 0 min 0
    
    while true; do
        iteration=$((iteration + 1))
        
        echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}📡 CHECK #$iteration - $(date '+%H:%M:%S')${NC}"
        echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
        
        # System resources
        echo -e "\n${YELLOW}🔧 System Resources:${NC}"
        check_cpu_memory
        
        # Connection stats
        echo -e "\n${YELLOW}🔌 Connection Statistics:${NC}"
        check_connections
        
        # Rate limit monitoring
        echo -e "\n${YELLOW}🚦 Rate Limit Monitoring:${NC}"
        check_rate_limited_ips
        
        # Every 6 iterations (~1 minute), show top attackers
        if [ $((iteration % 6)) -eq 0 ]; then
            show_top_attackers
        fi
        
        # Check for user input (non-blocking)
        read input
        if [ -n "$input" ]; then
            case "$input" in
                m|M) 
                    show_actions
                    read action
                    case "$action" in
                        b|B) block_ip ;;
                        u|U) unblock_ip ;;
                        r|R) show_recent_alerts ;;
                        l|L) show_rate_limit_stats ;;
                        d|D) show_deploy_log ;;
                        c|C) clear ;;
                        q|Q) 
                            echo -e "\n${GREEN}Monitoring stopped${NC}"
                            stty echo
                            exit 0
                            ;;
                    esac
                    ;;
            esac
        fi
        
        echo -e "\n${BLUE}Next check in ${CHECK_INTERVAL}s...${NC}"
        sleep "$CHECK_INTERVAL"
    done
}

# Handle Ctrl+C
cleanup() {
    stty echo
    echo -e "\n\n${GREEN}=== Monitoring Summary ===${NC}"
    echo "Total runtime: $(date -d@$SECONDS -u +%H:%M:%S)"
    echo "DOS Log file: $DOS_LOG_FILE"
    echo "Deploy Log file: $DEPLOY_LOG_FILE"
    echo -e "\n${YELLOW}Recent alerts:${NC}"
    tail -10 "$DOS_LOG_FILE" | grep -E "ALERT|WARNING" || echo "No recent alerts"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
    echo -e "${YELLOW}Try: sudo $0${NC}"
    exit 1
fi

# Check if bc is installed (for floating point math)
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Installing bc for calculations...${NC}"
    apt update && apt install -y bc
fi

# Run main function
main
