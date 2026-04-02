// Moodly automated tests — Node.js version
// Run: node test-node.js

let pass = 0, fail = 0, currentSuite = '';

function suite(name) { currentSuite = name; console.log(`\n\x1b[1m${name}\x1b[0m`); }

function assert(name, condition, detail) {
    if (condition) { pass++; console.log(`  \x1b[32m✓\x1b[0m ${name}`); }
    else { fail++; console.log(`  \x1b[31m✗\x1b[0m ${name}${detail ? ' — ' + detail : ''}`); }
}

function assertEqual(name, actual, expected) {
    const a = JSON.stringify(actual), e = JSON.stringify(expected);
    assert(name, a === e, a !== e ? `Förväntat: ${e}, Fick: ${a}` : '');
}

function assertGt(name, actual, min) {
    assert(name, actual > min, `${actual} borde vara > ${min}`);
}

// ========== MOCK SETUP ==========
const mockStore = {};
const localStorage = {
    getItem: (k) => mockStore[k] || null,
    setItem: (k, v) => { mockStore[k] = String(v); },
    removeItem: (k) => { delete mockStore[k]; },
    clear: () => { Object.keys(mockStore).forEach(k => delete mockStore[k]); }
};

const sok = true;
const PARENT_KEY = 'moodly';
let APK = PARENT_KEY;
let D = {places:[],placeCheckins:[],benchmarks:[],checkins:[],micro:[],xp:0,level:1,points:0,streak:0,firstVisit:true,baseline:null,userName:'',aiName:'Luna',personality:'warm',onboarded:null,alertsSeen:[],familyId:'',role:'self',familyProfiles:[],parentKey:'',unlockedAvatars:['default'],selectedAvatar:'default',dailyRewardClaimed:null,kommun:'',parentReactions:[],cheersSent:{}};

function ld() {
    try {
        const r = localStorage.getItem(APK);
        if (!r) return {...D};
        const d = JSON.parse(r);
        if (!d.places) d.places = [];
        if (!d.placeCheckins) d.placeCheckins = [];
        if (!d.familyProfiles) d.familyProfiles = [];
        if (!d.points) d.points = 0;
        if (!d.unlockedAvatars) d.unlockedAvatars = ['default'];
        if (!d.kommun) d.kommun = '';
        if (!d.parentReactions) d.parentReactions = [];
        if (!d.cheersSent) d.cheersSent = {};
        return d;
    } catch (e) { return {...D}; }
}

function sv(d) { D = d; localStorage.setItem(APK, JSON.stringify(d)); }

function getFullChildData(sk) {
    try { const r = localStorage.getItem(sk); if (!r) return null; return JSON.parse(r); } catch (e) { return null; }
}

function esc(s) { if (!s) return ''; return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

const PT = {
    school: {icon:'🏫',label:'Skola'}, home: {icon:'🏠',label:'Hem'},
    sport: {icon:'⚽',label:'Idrott'}, hobby: {icon:'🎨',label:'Hobby'}
};

// ========== SUITE 1: Data Model ==========
suite('1. Datamodell (localStorage)');

localStorage.clear();
APK = PARENT_KEY;

const d1 = {...D, userName: 'TestPappa', role: 'parent', kommun: 'Stockholm'};
sv(d1);
const loaded1 = ld();
assertEqual('Spara och ladda userName', loaded1.userName, 'TestPappa');
assertEqual('Spara och ladda role', loaded1.role, 'parent');
assertEqual('Spara och ladda kommun', loaded1.kommun, 'Stockholm');

localStorage.clear();
const empty = ld();
assertEqual('Tom ld() ger tomma places', empty.places, []);
assertEqual('Tom ld() ger tomma placeCheckins', empty.placeCheckins, []);
assertEqual('Tom ld() ger tomma familyProfiles', empty.familyProfiles, []);

const childKey1 = 'moodly_child_test1';
localStorage.setItem(childKey1, JSON.stringify({places: [{id:'p1',name:'Skola',type:'school'}], placeCheckins: [], role: 'child', userName: 'Maja'}));
APK = childKey1;
const cd1 = ld();
assertEqual('APK switch laddar rätt profil', cd1.userName, 'Maja');
assertEqual('Barnprofil har platser', cd1.places.length, 1);

APK = PARENT_KEY;
sv(d1);
assertEqual('Tillbaka till parent key', ld().userName, 'TestPappa');

const fullChild = getFullChildData(childKey1);
assert('getFullChildData returnerar data', fullChild !== null);
assertEqual('getFullChildData rätt namn', fullChild.userName, 'Maja');
assert('getFullChildData null för saknad nyckel', getFullChildData('nonexistent') === null);

// ========== SUITE 2: Onboarding ==========
suite('2. Onboarding (barn + platser)');

localStorage.clear();
APK = PARENT_KEY;

const d2 = {...D, firstVisit: false, userName: 'Marcus', kommun: 'Göteborg', onboarded: new Date().toISOString(), role: 'parent', familyId: 'fam_' + Date.now(), places: [], familyProfiles: []};

const children = [
    {name: 'Maja', ageGroup: '7-9', places: [{name:'Skola',type:'school'},{name:'Idrott',type:'sport'},{name:'Hem',type:'home'}]},
    {name: 'Leo', ageGroup: '4-6', places: [{name:'Förskola',type:'school'},{name:'Hem',type:'home'}]}
];

children.forEach((child, ci) => {
    const id = 'child_' + Date.now() + '_' + ci;
    const storageKey = 'moodly_child_' + id;
    const childPlaces = child.places.map((p, pi) => ({id: 'p_' + Date.now() + '_' + ci + '_' + pi, name: p.name, type: p.type, osmId: '', address: '', lat: null, lng: null}));
    d2.familyProfiles.push({id, name: child.name, ageGroup: child.ageGroup, storageKey});
    localStorage.setItem(storageKey, JSON.stringify({
        places: childPlaces, placeCheckins: [], role: 'child', userName: child.name, familyId: d2.familyId, parentKey: PARENT_KEY, kommun: d2.kommun,
        unlockedAvatars: ['default'], selectedAvatar: 'default'
    }));
});
sv(d2);

const saved2 = ld();
assertEqual('Förälder har 2 barn', saved2.familyProfiles.length, 2);
assertEqual('Barn 1 = Maja', saved2.familyProfiles[0].name, 'Maja');
assertEqual('Barn 2 = Leo', saved2.familyProfiles[1].name, 'Leo');

const majaData = getFullChildData(saved2.familyProfiles[0].storageKey);
assert('Majas data existerar', majaData !== null);
assertEqual('Maja har 3 platser', majaData.places.length, 3);

const leoData = getFullChildData(saved2.familyProfiles[1].storageKey);
assert('Leos data existerar', leoData !== null);
assertEqual('Leo har 2 platser', leoData.places.length, 2);

const allIds = [...majaData.places, ...leoData.places].map(p => p.id);
assertEqual('Alla plats-ID unika', new Set(allIds).size, allIds.length);
assertEqual('Förälder har inga egna platser', saved2.places.length, 0);

// ========== SUITE 3: Check-in ==========
suite('3. Check-in-flöde');

const majaKey = saved2.familyProfiles[0].storageKey;
APK = majaKey;

let maja = ld();
const schoolP = maja.places.find(p => p.type === 'school');
const sportP = maja.places.find(p => p.type === 'sport');
const homeP = maja.places.find(p => p.type === 'home');

maja.placeCheckins.push({ts: new Date().toISOString(), placeId: schoolP.id, score: 3, comment: 'Okej dag', tags: ['Vanlig dag', 'Trött']});
maja.placeCheckins.push({ts: new Date().toISOString(), placeId: sportP.id, score: 5, comment: '', tags: ['Vann', 'Kompisar']});
maja.placeCheckins.push({ts: new Date().toISOString(), placeId: homeP.id, score: 4, comment: 'Bra kväll', tags: ['Familj']});
sv(maja);

maja = ld();
assertEqual('3 check-ins sparade', maja.placeCheckins.length, 3);
assertEqual('Skolscore = 3', maja.placeCheckins.find(c => c.placeId === schoolP.id).score, 3);
assertEqual('Tags på skola', maja.placeCheckins.find(c => c.placeId === schoolP.id).tags.length, 2);
assertEqual('Kommentar sparad', maja.placeCheckins.find(c => c.placeId === schoolP.id).comment, 'Okej dag');
assertEqual('Sportscore = 5', maja.placeCheckins.find(c => c.placeId === sportP.id).score, 5);

APK = PARENT_KEY;

// ========== SUITE 4: Isolering ==========
suite('4. Plats-barn-isolering');

const d4 = ld();
const leoKey = d4.familyProfiles[1].storageKey;

const maja4 = getFullChildData(majaKey);
const leo4 = getFullChildData(leoKey);

const majaIds = new Set(maja4.places.map(p => p.id));
const leoIds = new Set(leo4.places.map(p => p.id));
let overlap = false;
majaIds.forEach(id => { if (leoIds.has(id)) overlap = true; });
assert('Inga gemensamma plats-ID', !overlap);
assertEqual('Leo har 0 check-ins', leo4.placeCheckins.length, 0);
assertGt('Maja har check-ins', maja4.placeCheckins.length, 0);

// Add place to Leo, verify Maja unaffected
leo4.places.push({id: 'p_leo_park', name: 'Parken', type: 'hobby'});
localStorage.setItem(leoKey, JSON.stringify(leo4));

assertEqual('Leo nu 3 platser', getFullChildData(leoKey).places.length, 3);
assertEqual('Maja fortfarande 3', getFullChildData(majaKey).places.length, 3);
assert('Parken hos Leo', getFullChildData(leoKey).places.some(p => p.name === 'Parken'));
assert('Parken inte hos Maja', !getFullChildData(majaKey).places.some(p => p.name === 'Parken'));

// ========== SUITE 5: addPlaceToChild ==========
suite('5. addPlaceToChild()');

function addPlaceToChild(storageKey, type, defaultName) {
    const cd = getFullChildData(storageKey);
    if (!cd) return null;
    const count = (cd.places || []).filter(p => p.type === type).length;
    const name = count ? defaultName + ' ' + (count + 1) : defaultName;
    const place = {id: 'p_' + Date.now() + '_' + Math.random().toString(36).slice(2,6), name, type, osmId: '', address: '', lat: null, lng: null};
    cd.places.push(place);
    localStorage.setItem(storageKey, JSON.stringify(cd));
    return place;
}

const beforeLeo = getFullChildData(leoKey).places.length;
const added = addPlaceToChild(leoKey, 'school', 'Skola');
assert('Plats skapad', added !== null);
assertEqual('Namn: Skola 2', added.name, 'Skola 2');
assert('Unikt ID', added.id.length > 12);
assertEqual('En plats tillagd', getFullChildData(leoKey).places.length, beforeLeo + 1);
assertEqual('Maja opåverkad', getFullChildData(majaKey).places.length, 3);

// ========== SUITE 6: removeChild skydd ==========
suite('6. removeChild — skydd sista barnet');

localStorage.clear();
APK = PARENT_KEY;

sv({...D, role: 'parent', familyProfiles: [{id:'c1', name:'Enda', storageKey:'moodly_child_c1'}]});
localStorage.setItem('moodly_child_c1', JSON.stringify({places:[], placeCheckins:[]}));

function removeChild(idx) {
    const d = ld();
    if (!d.familyProfiles[idx]) return 'not_found';
    if (d.familyProfiles.length <= 1) return 'blocked';
    localStorage.removeItem(d.familyProfiles[idx].storageKey);
    d.familyProfiles.splice(idx, 1); sv(d);
    return 'removed';
}

assertEqual('Blockerar borttagning av sista barn', removeChild(0), 'blocked');
assertEqual('Barnet finns kvar', ld().familyProfiles.length, 1);

const d6 = ld();
d6.familyProfiles.push({id:'c2', name:'Barn 2', storageKey:'moodly_child_c2'});
localStorage.setItem('moodly_child_c2', JSON.stringify({places:[], placeCheckins:[]}));
sv(d6);

assertEqual('Kan ta bort med 2 barn', removeChild(0), 'removed');
assertEqual('Ett barn kvar', ld().familyProfiles.length, 1);
assertEqual('Rätt barn kvar', ld().familyProfiles[0].name, 'Barn 2');

// ========== SUITE 7: Baseline & Z-score ==========
suite('7. Baseline & Z-score');

function computeBaseline(checkins, placeId) {
    const pc = checkins.filter(c => c.placeId === placeId);
    if (pc.length < 7) return null;
    const scores = pc.map(c => c.score);
    const mean = scores.reduce((a,b) => a+b, 0) / scores.length;
    const variance = scores.reduce((a,s) => a + Math.pow(s-mean, 2), 0) / scores.length;
    const stddev = Math.sqrt(variance) || 0.5;
    return {mean: Math.round(mean*100)/100, stddev: Math.round(stddev*100)/100, n: pc.length};
}

function computeZScore(score, baseline) {
    if (!baseline) return 0;
    return Math.round(((score - baseline.mean) / baseline.stddev) * 100) / 100;
}

const few = Array.from({length:5}, (_,i) => ({placeId:'p1', score:3+(i%2), ts:new Date().toISOString()}));
assert('Ingen baseline med <7 punkter', computeBaseline(few, 'p1') === null);

const enough = Array.from({length:14}, (_,i) => ({placeId:'p1', score:3+Math.sin(i)*0.5, ts:new Date().toISOString()}));
const bl = computeBaseline(enough, 'p1');
assert('Baseline med 14 punkter', bl !== null);
assertGt('Mean > 0', bl.mean, 0);
assertGt('Stddev > 0', bl.stddev, 0);
assertEqual('N = 14', bl.n, 14);

assertGt('Högt score → positiv z', computeZScore(5, bl), 0);
assert('Lågt score → negativ z', computeZScore(1, bl) < 0);
assertEqual('Score = mean → z ≈ 0', computeZScore(bl.mean, bl), 0);
assertEqual('Null baseline → z = 0', computeZScore(3, null), 0);

// ========== SUITE 8: Heatmap ==========
suite('8. Heatmap-data');

localStorage.clear();
APK = PARENT_KEY;

const hmChildKey = 'moodly_child_hm1';
const hmPlaceId = 'p_school_hm';
const hmCheckins = [];
for (let i = 0; i < 28; i++) {
    const date = new Date(Date.now() - i * 864e5);
    hmCheckins.push({placeId: hmPlaceId, score: 2 + (date.getDay() % 3), ts: date.toISOString(), tags: []});
}
localStorage.setItem(hmChildKey, JSON.stringify({places:[{id:hmPlaceId,name:'Testskola',type:'school'}], placeCheckins:hmCheckins, role:'child', userName:'HmBarn'}));
sv({...D, role:'parent', familyProfiles:[{id:'hm1', name:'HmBarn', storageKey:hmChildKey}]});

function buildHeatmapData(d) {
    const result = [];
    (d.familyProfiles||[]).forEach(fp => {
        const cd = getFullChildData(fp.storageKey);
        if (!cd || !cd.places || !cd.placeCheckins) return;
        const places = [];
        cd.places.forEach(p => {
            const days = [null,null,null,null,null,null,null];
            const counts = [0,0,0,0,0,0,0], totals = [0,0,0,0,0,0,0];
            cd.placeCheckins.filter(c => c.placeId === p.id && new Date(c.ts).getTime() > Date.now()-28*864e5).forEach(c => {
                let dow = (new Date(c.ts).getDay()+6)%7;
                totals[dow] += c.score; counts[dow]++;
            });
            for (let i=0; i<7; i++) { if (counts[i]) days[i] = Math.round(totals[i]/counts[i]*10)/10; }
            places.push({name:p.name, icon:'🏫', days});
        });
        if (places.length) result.push({childName:fp.name, places});
    });
    return result;
}

const hm = buildHeatmapData(ld());
assertEqual('1 barn i heatmap', hm.length, 1);
assertEqual('Rätt namn', hm[0].childName, 'HmBarn');
assertEqual('1 plats', hm[0].places.length, 1);
assertEqual('7 dagar', hm[0].places[0].days.length, 7);
assertGt('Flera dagar har data', hm[0].places[0].days.filter(d => d !== null).length, 4);

// ========== SUITE 9: Pattern Detection ==========
suite('9. Mönsterdetektion');

localStorage.clear();
APK = PARENT_KEY;

const patChildKey = 'moodly_child_pat1';
const patPlaceId = 'p_school_pat';
const patCheckins = [];
for (let i = 0; i < 14; i++) {
    const date = new Date(Date.now() - i * 864e5);
    const dow = date.getDay();
    patCheckins.push({placeId:patPlaceId, score: dow===1?1:4, ts:date.toISOString(), tags: dow===1?['Kompisar','Trött']:['Rolig lektion']});
}
localStorage.setItem(patChildKey, JSON.stringify({places:[{id:patPlaceId,name:'Testskola',type:'school'}], placeCheckins:patCheckins, role:'child', userName:'PatBarn'}));
sv({...D, role:'parent', familyProfiles:[{id:'pat1',name:'PatBarn',storageKey:patChildKey}]});

function detectPatterns(d) {
    const patterns = [];
    const dayNames = ['måndagar','tisdagar','onsdagar','torsdagar','fredagar','lördagar','söndagar'];
    (d.familyProfiles||[]).forEach(fp => {
        const cd = getFullChildData(fp.storageKey);
        if (!cd || !cd.places || !cd.placeCheckins) return;
        cd.places.forEach(p => {
            const recent14 = cd.placeCheckins.filter(c => c.placeId === p.id && new Date(c.ts).getTime() > Date.now()-14*864e5);
            if (recent14.length < 3) return;
            const avg14 = recent14.reduce((a,c)=>a+c.score,0)/recent14.length;
            const dayScores = {};
            recent14.forEach(c => {
                const dow = (new Date(c.ts).getDay()+6)%7;
                if (!dayScores[dow]) dayScores[dow] = {total:0,count:0};
                dayScores[dow].total += c.score; dayScores[dow].count++;
            });
            let worstDay=-1, worstAvg=5;
            Object.entries(dayScores).forEach(([day,s]) => {
                if (s.count<2) return;
                const avg = s.total/s.count;
                if (avg<worstAvg) {worstAvg=avg; worstDay=+day;}
            });
            if (worstDay>=0 && worstAvg<avg14-0.5)
                patterns.push({type:'warning', text:`${fp.name} sämre på ${dayNames[worstDay]}`});

            const recent7 = cd.placeCheckins.filter(c => c.placeId===p.id && new Date(c.ts).getTime()>Date.now()-7*864e5);
            const tagCount = {};
            recent7.forEach(c => (c.tags||[]).forEach(t => {tagCount[t]=(tagCount[t]||0)+1}));
            Object.entries(tagCount).forEach(([tag,count]) => {
                if (count >= 3) patterns.push({type:'neutral', text:`"${tag}" återkommande`});
            });
        });
    });
    return patterns;
}

const patterns = detectPatterns(ld());
assertGt('Hittade mönster', patterns.length, 0);
assert('Detekterade dålig veckodag', patterns.some(p => p.text.includes('sämre på')));

// ========== SUITE 10: Tag Impact ==========
suite('10. Tagg-impact');

function buildTagImpact(d) {
    const result = [];
    (d.familyProfiles||[]).forEach(fp => {
        const cd = getFullChildData(fp.storageKey);
        if (!cd || !cd.placeCheckins) return;
        const recent = cd.placeCheckins.filter(c => new Date(c.ts).getTime() > Date.now()-30*864e5);
        if (recent.length < 5) return;
        const overallAvg = recent.reduce((a,c)=>a+c.score,0)/recent.length;
        const tagStats = {};
        recent.forEach(c => (c.tags||[]).forEach(tag => {
            if (!tagStats[tag]) tagStats[tag]={total:0,count:0};
            tagStats[tag].total+=c.score; tagStats[tag].count++;
        }));
        const tags = Object.entries(tagStats).filter(([,s])=>s.count>=2).map(([tag,s])=>({
            tag, impact:Math.round((s.total/s.count-overallAvg)*10)/10, count:s.count
        })).sort((a,b)=>a.impact-b.impact);
        if (tags.length) result.push({childName:fp.name, tags});
    });
    return result;
}

const impact = buildTagImpact(ld());
assertGt('Har tag-impact resultat', impact.length, 0);
if (impact.length) {
    const negTag = impact[0].tags.find(t => t.tag==='Kompisar'||t.tag==='Trött');
    assert('Negativ tagg har neg impact', negTag && negTag.impact < 0);
    const posTag = impact[0].tags.find(t => t.tag==='Rolig lektion');
    assert('Positiv tagg har pos impact', posTag && posTag.impact > 0);
}

// ========== SUITE 11: Sync Status ==========
suite('11. Sync-status');

function getSyncStatus() {
    const q = JSON.parse(localStorage.getItem('moodly_pending') || '[]');
    if (q.length) return 'syncing_' + q.length;
    return 'synced';
}

localStorage.removeItem('moodly_pending');
assertEqual('Ingen kö → synkad', getSyncStatus(), 'synced');
localStorage.setItem('moodly_pending', JSON.stringify([{table:'places',op:'upsert',data:{}}]));
assertEqual('Med kö → synkar', getSyncStatus(), 'syncing_1');
localStorage.removeItem('moodly_pending');

// ========== SUITE 12: XSS ==========
suite('12. XSS-skydd');

assertEqual('Escapar <script>', esc('<script>alert("xss")</script>'), '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;');
assertEqual('Escapar &', esc('A & B'), 'A &amp; B');
assertEqual('Null input', esc(null), '');
assertEqual('Undefined input', esc(undefined), '');
assertEqual('Tom sträng', esc(''), '');
assertEqual('Normal text oförändrad', esc('Maja gillar skolan'), 'Maja gillar skolan');

// ========== SUMMARY ==========
console.log('\n' + '='.repeat(50));
if (fail === 0) {
    console.log(`\x1b[32m\x1b[1mAlla ${pass} tester passerade ✓\x1b[0m`);
} else {
    console.log(`\x1b[31m\x1b[1m${fail} av ${pass+fail} tester misslyckades\x1b[0m`);
}
console.log('='.repeat(50));
process.exit(fail > 0 ? 1 : 0);
