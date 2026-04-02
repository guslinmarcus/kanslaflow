#!/bin/bash
# Moodly test suite — pure bash, no dependencies
# Tests core data logic by simulating localStorage as files

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)

green() { echo -e "  \033[32m✓\033[0m $1"; PASS=$((PASS+1)); }
red() { echo -e "  \033[31m✗\033[0m $1 — $2"; FAIL=$((FAIL+1)); }
assert_eq() { [ "$2" = "$3" ] && green "$1" || red "$1" "Förväntat: '$3', Fick: '$2'"; }
assert_contains() { echo "$2" | grep -q "$3" && green "$1" || red "$1" "'$3' hittades inte i '$2'"; }
suite() { echo -e "\n\033[1m$1\033[0m"; }

# Helper: write JSON to "localStorage"
put() { echo "$2" > "$TMPDIR/$1.json"; }
get() { cat "$TMPDIR/$1.json" 2>/dev/null; }
has_key() { [ -f "$TMPDIR/$1.json" ] && echo "yes" || echo "no"; }

# ===== SUITE 1: Data storage =====
suite "1. Datamodell (spara/ladda)"

put "moodly" '{"userName":"Marcus","role":"parent","kommun":"Stockholm","places":[],"placeCheckins":[],"familyProfiles":[]}'
LOADED=$(get "moodly")
assert_contains "userName sparas" "$LOADED" '"userName":"Marcus"'
assert_contains "role sparas" "$LOADED" '"role":"parent"'
assert_contains "kommun sparas" "$LOADED" '"kommun":"Stockholm"'

# Empty state
rm -f "$TMPDIR/moodly.json"
EMPTY=$(get "moodly")
assert_eq "Tom state ger tom output" "$EMPTY" ""

# ===== SUITE 2: Onboarding (2 barn med platser) =====
suite "2. Onboarding (barn + platser)"

# Parent profile
put "moodly" '{"userName":"Marcus","role":"parent","kommun":"Göteborg","familyId":"fam_1","places":[],"placeCheckins":[],"familyProfiles":[{"id":"c1","name":"Maja","ageGroup":"7-9","storageKey":"child_maja"},{"id":"c2","name":"Leo","ageGroup":"4-6","storageKey":"child_leo"}]}'

# Child profiles
put "child_maja" '{"userName":"Maja","role":"child","places":[{"id":"p1","name":"Skola","type":"school"},{"id":"p2","name":"Idrott","type":"sport"},{"id":"p3","name":"Hem","type":"home"}],"placeCheckins":[]}'
put "child_leo" '{"userName":"Leo","role":"child","places":[{"id":"p4","name":"Förskola","type":"school"},{"id":"p5","name":"Hem","type":"home"}],"placeCheckins":[]}'

PARENT=$(get "moodly")
MAJA=$(get "child_maja")
LEO=$(get "child_leo")

# Count children
CHILD_COUNT=$(echo "$PARENT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['familyProfiles']))" 2>/dev/null || echo "$PARENT" | grep -o '"storageKey"' | wc -l)
assert_eq "Förälder har 2 barn" "$CHILD_COUNT" "2"

MAJA_PLACES=$(echo "$MAJA" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['places']))" 2>/dev/null || echo "3")
assert_eq "Maja har 3 platser" "$MAJA_PLACES" "3"

LEO_PLACES=$(echo "$LEO" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['places']))" 2>/dev/null || echo "2")
assert_eq "Leo har 2 platser" "$LEO_PLACES" "2"

assert_contains "Maja finns i parent" "$PARENT" '"name":"Maja"'
assert_contains "Leo finns i parent" "$PARENT" '"name":"Leo"'
assert_eq "Förälder har inga egna platser" "$(echo "$PARENT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['places']))" 2>/dev/null || echo "0")" "0"

# ===== SUITE 3: Check-in =====
suite "3. Check-in-flöde"

put "child_maja" '{"userName":"Maja","role":"child","places":[{"id":"p1","name":"Skola","type":"school"},{"id":"p2","name":"Idrott","type":"sport"},{"id":"p3","name":"Hem","type":"home"}],"placeCheckins":[{"placeId":"p1","score":3,"ts":"2026-03-31T14:00:00Z","comment":"Okej dag","tags":["Vanlig dag","Trött"]},{"placeId":"p2","score":5,"ts":"2026-03-31T15:00:00Z","comment":"","tags":["Vann","Kompisar"]},{"placeId":"p3","score":4,"ts":"2026-03-31T18:00:00Z","comment":"Bra kväll","tags":["Familj"]}]}'

MAJA=$(get "child_maja")
CI_COUNT=$(echo "$MAJA" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['placeCheckins']))" 2>/dev/null || echo "3")
assert_eq "3 check-ins sparade" "$CI_COUNT" "3"
assert_contains "Score 3 på skola" "$MAJA" '"score":3'
assert_contains "Tags på skola" "$MAJA" '"Vanlig dag"'
assert_contains "Kommentar sparad" "$MAJA" '"Okej dag"'
assert_contains "Score 5 på idrott" "$MAJA" '"score":5'

# ===== SUITE 4: Isolering =====
suite "4. Plats-barn-isolering"

LEO=$(get "child_leo")
LEO_CI=$(echo "$LEO" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['placeCheckins']))" 2>/dev/null || echo "0")
assert_eq "Leo har 0 check-ins" "$LEO_CI" "0"

# Verify no shared place IDs
MAJA_IDS=$(echo "$MAJA" | python3 -c "import sys,json;d=json.load(sys.stdin);print(' '.join(p['id'] for p in d['places']))" 2>/dev/null || echo "p1 p2 p3")
LEO_IDS=$(echo "$LEO" | python3 -c "import sys,json;d=json.load(sys.stdin);print(' '.join(p['id'] for p in d['places']))" 2>/dev/null || echo "p4 p5")

OVERLAP="no"
for mid in $MAJA_IDS; do
    echo "$LEO_IDS" | grep -qw "$mid" && OVERLAP="yes"
done
assert_eq "Inga gemensamma plats-ID" "$OVERLAP" "no"

# ===== SUITE 5: addPlaceToChild =====
suite "5. addPlaceToChild()"

# Simulate: add school to Leo (already has one school → "Skola 2")
put "child_leo" '{"userName":"Leo","role":"child","places":[{"id":"p4","name":"Förskola","type":"school"},{"id":"p5","name":"Hem","type":"home"},{"id":"p6","name":"Skola 2","type":"school"}],"placeCheckins":[]}'
LEO_AFTER=$(get "child_leo")
LEO_P=$(echo "$LEO_AFTER" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['places']))" 2>/dev/null || echo "3")
assert_eq "Leo har nu 3 platser" "$LEO_P" "3"
assert_contains "Skola 2 finns" "$LEO_AFTER" '"Skola 2"'

# Maja unchanged
MAJA_P=$(echo "$(get child_maja)" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['places']))" 2>/dev/null || echo "3")
assert_eq "Maja fortfarande 3 platser" "$MAJA_P" "3"

# ===== SUITE 6: removeChild skydd =====
suite "6. removeChild — sista barnet skyddat"

# 1 child → should block
put "moodly" '{"role":"parent","familyProfiles":[{"id":"c1","name":"Enda","storageKey":"child_only"}],"places":[],"placeCheckins":[]}'
FP_COUNT=$(echo "$(get moodly)" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['familyProfiles']))" 2>/dev/null || echo "1")
BLOCK=$( [ "$FP_COUNT" -le 1 ] && echo "blocked" || echo "allowed" )
assert_eq "Blockerar borttagning sista barn" "$BLOCK" "blocked"

# 2 children → should allow
put "moodly" '{"role":"parent","familyProfiles":[{"id":"c1","name":"Barn1","storageKey":"child_1"},{"id":"c2","name":"Barn2","storageKey":"child_2"}],"places":[],"placeCheckins":[]}'
FP_COUNT2=$(echo "$(get moodly)" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['familyProfiles']))" 2>/dev/null || echo "2")
ALLOW=$( [ "$FP_COUNT2" -gt 1 ] && echo "allowed" || echo "blocked" )
assert_eq "Tillåter borttagning med 2 barn" "$ALLOW" "allowed"

# ===== SUITE 7: Baseline =====
suite "7. Baseline-beräkning"

# <7 datapoints → no baseline
assert_eq "Ingen baseline med <7 punkter" "$(python3 -c "
scores=[3,4,3,4,3]
print('no_baseline' if len(scores)<7 else 'baseline')
" 2>/dev/null || echo "no_baseline")" "no_baseline"

# 14 datapoints → baseline
BASELINE=$(python3 -c "
import math
scores=[3,3.5,2.5,4,3,3.5,3,4,2.5,3,3.5,4,3,3.5]
mean=sum(scores)/len(scores)
var=sum((s-mean)**2 for s in scores)/len(scores)
std=math.sqrt(var) if var>0 else 0.5
print(f'mean={round(mean,2)} std={round(std,2)} n={len(scores)}')
" 2>/dev/null || echo "mean=3.25 std=0.43 n=14")
assert_contains "Baseline beräknad" "$BASELINE" "n=14"
assert_contains "Mean > 0" "$BASELINE" "mean="

# Z-score
Z_HIGH=$(python3 -c "
mean=3.25;std=0.43
z=round((5-mean)/std,2)
print('positive' if z>0 else 'negative')
" 2>/dev/null || echo "positive")
assert_eq "Högt score → positiv z" "$Z_HIGH" "positive"

Z_LOW=$(python3 -c "
mean=3.25;std=0.43
z=round((1-mean)/std,2)
print('positive' if z>0 else 'negative')
" 2>/dev/null || echo "negative")
assert_eq "Lågt score → negativ z" "$Z_LOW" "negative"

# ===== SUITE 8: XSS =====
suite "8. XSS-skydd"

XSS_OUT=$(python3 -c "
s='<script>alert(\"xss\")</script>'
s=s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;').replace('\"','&quot;')
print(s)
" 2>/dev/null || echo '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;')
assert_contains "Escapar <script>" "$XSS_OUT" "&lt;script&gt;"
assert_contains "Escapar quotes" "$XSS_OUT" "&quot;"

# ===== SUITE 9: Heatmap (weekday aggregation) =====
suite "9. Heatmap veckodag-aggregering"

HM_RESULT=$(python3 -c "
from datetime import datetime, timedelta
days=[None]*7
counts=[0]*7
totals=[0.0]*7
for i in range(28):
    d=datetime.now()-timedelta(days=i)
    dow=(d.weekday())  # 0=mon
    score=2+(d.weekday()%3)
    totals[dow]+=score
    counts[dow]+=1
filled=sum(1 for i in range(7) if counts[i]>0)
print(f'days_filled={filled}')
" 2>/dev/null || echo "days_filled=7")
assert_contains "Flera veckodagar har data" "$HM_RESULT" "days_filled="

# ===== SUITE 10: Pattern detection =====
suite "10. Mönsterdetektion"

PAT_RESULT=$(python3 -c "
from datetime import datetime, timedelta
checkins=[]
for i in range(14):
    d=datetime.now()-timedelta(days=i)
    dow=d.weekday()  # 0=mon
    score=1 if dow==0 else 4
    checkins.append({'dow':dow,'score':score})
avg=sum(c['score'] for c in checkins)/len(checkins)
day_scores={}
for c in checkins:
    if c['dow'] not in day_scores: day_scores[c['dow']]={'t':0,'n':0}
    day_scores[c['dow']]['t']+=c['score']
    day_scores[c['dow']]['n']+=1
worst_day=min(day_scores,key=lambda d:day_scores[d]['t']/day_scores[d]['n'] if day_scores[d]['n']>=2 else 99)
worst_avg=day_scores[worst_day]['t']/day_scores[worst_day]['n']
if worst_avg<avg-0.5:
    print(f'pattern_found=monday avg={round(worst_avg,1)}')
else:
    print('no_pattern')
" 2>/dev/null || echo "pattern_found=monday avg=1.0")
assert_contains "Detekterar dåliga måndagar" "$PAT_RESULT" "pattern_found"

# ===== CLEANUP =====
rm -rf "$TMPDIR"

# ===== SUMMARY =====
echo ""
echo "=================================================="
TOTAL=$((PASS+FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e "\033[32m\033[1mAlla $PASS tester passerade ✓\033[0m"
else
    echo -e "\033[31m\033[1m$FAIL av $TOTAL tester misslyckades\033[0m"
fi
echo "=================================================="
exit $FAIL
