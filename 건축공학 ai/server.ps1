# server.ps1
# 터미널 창을 닫지 말고 켜두세요!
$port = 3000
$dataFile = Join-Path $PSScriptRoot "latest_design.json"

# HttpListener 설정
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:${port}/")

try {
    $listener.Start()
} catch {
    Write-Host "포트가 이미 사용 중이거나 관리자 권한이 필요할 수 있습니다." -ForegroundColor Red
    exit
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " 🚀 [AI Architect] 로컬 통신 서버 (PowerShell) 실행 중!" -ForegroundColor Cyan
Write-Host "- 수신 엔드포인트: http://localhost:${port}/export (웹에서 송신)"
Write-Host "- 송신 엔드포인트: http://localhost:${port}/latest (SketchUp에서 수신)"
Write-Host "종료하려면 이 터미널에서 Ctrl+C 를 누르세요." -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor Cyan

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        # CORS Headers 설정
        $response.AppendHeader("Access-Control-Allow-Origin", "*")
        $response.AppendHeader("Access-Control-Allow-Methods", "OPTIONS, POST, GET")
        $response.AppendHeader("Access-Control-Allow-Headers", "Content-Type")

        if ($request.HttpMethod -eq 'OPTIONS') {
            $response.StatusCode = 204
            $response.Close()
            continue
        }

        # 1. 웹 브라우저에서 모델 데이터 수신 (POST /export)
        if ($request.HttpMethod -eq 'POST' -and $request.Url.AbsolutePath -eq '/export') {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()

            try {
                # JSON을 파싱해서 대안 이름을 로그에 찍어줍니다
                $obj = $body | ConvertFrom-Json
                $altName = $obj.buildingInfo.selectedAlternative
                
                Set-Content -Path $dataFile -Value $body -Encoding UTF8
                Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] ✅ 웹 브라우저에서 새로운 건축 대안 ($altName) 을 수신하고 저장했습니다!" -ForegroundColor Green
                
                $responseString = '{"success":true,"message":"Data saved successfully locally."}'
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.StatusCode = 200
            } catch {
                Write-Host "처리 중 에러 발생." -ForegroundColor Red
                $response.StatusCode = 500
            }
        }
        # 2. SketchUp에서 모델 데이터 요청 (GET /latest)
        elseif ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath -eq '/latest') {
            if (Test-Path $dataFile) {
                # -Raw 옵션은 PS 3.0 이상에서만. 안전하게 읽으려면:
                $responseString = [System.IO.File]::ReadAllText($dataFile, [System.Text.Encoding]::UTF8)
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.StatusCode = 200
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] 📤 SketchUp으로 데이터를 전송했습니다." -ForegroundColor Blue
            } else {
                $responseString = '{"success":false,"error":"No data found. Please export from web first."}'
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.StatusCode = 404
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ❌ SketchUp에서 요청이 왔으나 아직 저장된 대안이 없습니다." -ForegroundColor Red
            }
        } else {
            $response.StatusCode = 404
        }
        $response.Close()
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
