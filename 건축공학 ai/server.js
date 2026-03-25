// server.js
// 단일 파일로 동작하는 의존성 없는(zero-dependency) Node.js 로컬 서버 포트입니다.
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3000;
const DATA_FILE = path.join(__dirname, 'latest_design.json');

const server = http.createServer((req, res) => {
    // CORS Header 설정 (웹 브라우저에서 요청 가능하도록)
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'OPTIONS, POST, GET');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    // Preflight 요청 처리
    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
    }

    // 1. 웹 브라우저에서 모델 데이터 수신 (POST /export)
    if (req.method === 'POST' && req.url === '/export') {
        let body = '';
        req.on('data', chunk => {
            body += chunk.toString();
        });
        
        req.on('end', () => {
            try {
                const data = JSON.parse(body);
                fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2), 'utf8');
                console.log(`\n[${new Date().toLocaleTimeString()}] ✅ 새로운 AI 건축 대안 데이터가 수신되어 저장되었습니다.`);
                console.log(`  - 모델ID: ${data.metadata.projectID}`);
                console.log(`  - 선택 모델: ${data.buildingInfo.selectedAlternative}`);
                console.log(`  - 용도: ${data.buildingInfo.use}, 층수: ${data.buildingInfo.floors}층`);
                
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, message: 'Data saved successfully locally.' }));
            } catch (e) {
                console.error('JSON 파싱 에러:', e);
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, error: 'Invalid JSON format' }));
            }
        });
    } 
    // 2. SketchUp에서 모델 데이터 요청 (GET /latest)
    else if (req.method === 'GET' && req.url === '/latest') {
        if (fs.existsSync(DATA_FILE)) {
            const data = fs.readFileSync(DATA_FILE, 'utf8');
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(data);
            console.log(`[${new Date().toLocaleTimeString()}] 📤 SketchUp으로 데이터를 전송했습니다.`);
        } else {
            res.writeHead(404, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: false, error: 'No data found. Please export from web first.' }));
            console.log(`[${new Date().toLocaleTimeString()}] ❌ SketchUp이 데이터를 요청했으나, 아직 저장된 대안이 없습니다.`);
        }
    } 
    // 그 외 잘못된 요청
    else {
        res.writeHead(404);
        res.end('Not Found');
    }
});

server.listen(PORT, () => {
    console.log('==================================================');
    console.log(`🚀 [AI Architect] 로컬 통신 서버가 실행되었습니다!`);
    console.log(`- 수신 엔드포인트: http://localhost:${PORT}/export (웹에서 송신)`);
    console.log(`- 송신 엔드포인트: http://localhost:${PORT}/latest (SketchUp에서 수신)`);
    console.log('==================================================');
    console.log('웹 브라우저에서 대안을 SketchUp으로 내보내면 이곳 터미널에 로그가 표시됩니다.');
});
