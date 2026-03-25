# sketchup_local_server.rb
# =========================================================================
# 💡 스케치업 루비 콘솔에 이 코드를 모두 복사해서 다시 붙여넣고 엔터를 누르세요!
# (기존 서버 오류들을 보완한 최신 강력한 버전입니다.)
# =========================================================================
require 'socket'
require 'json'
require 'sketchup.rb'

module AIArchitectServer
  @server_running = false
  @server_thread = nil
  @server = nil
  PORT = 3000

  def self.start_server
    if @server_running
      UI.messagebox("✅ AI Architect 서버가 이미 포트 #{PORT}에서 실행 중입니다.")
      return
    end

    begin
      # 0.0.0.0을 사용하여 통신을 더 넓게 허용. (localhost와 127.0.0.1 IPv6 충돌 방지)
      @server = TCPServer.new('0.0.0.0', PORT)
      @server_running = true
      
      puts "=========================================================="
      puts "🚀 [AI Architect] 향상된 웹 브릿지 서버를 실행했습니다!"
      puts "🔗 수신 대기 주소: 127.0.0.1:#{PORT}"
      puts "=========================================================="
      UI.messagebox("🚀 스케치업 내장 서버가 정상 시작되었습니다!\n\n문제가 수정된 새로운 버전입니다. 기존 스케치업 안에서 이 서버 스크립트가 돌아가는 상태로 두고, 웹 브라우저에서 모델 [SketchUp 연동] 버튼을 다시 눌러보세요.")

      @server_thread = Thread.new do
        while @server_running
          begin
            client = @server.accept
            
            # 1. HTTP 요청 라인 파싱 (GET / OPTIONS / POST 등)
            request_line = client.gets
            next unless request_line
            
            # 2. HTTP 헤더 파싱 (대소문자 구분을 방지하기 위해 모두 소문자화)
            headers = {}
            while (line = client.gets)
              line.strip!
              break if line.empty?
              key, value = line.split(': ', 2)
              headers[key.downcase] = value if key && value
            end
            
            # 3. CORS Preflight (OPTIONS 요청) 완벽 처리
            if request_line.start_with?("OPTIONS")
              response = [
                "HTTP/1.1 204 No Content",
                "Access-Control-Allow-Origin: *",
                "Access-Control-Allow-Methods: POST, GET, OPTIONS",
                "Access-Control-Allow-Headers: Content-Type",
                "Access-Control-Max-Age: 86400",
                "Connection: close",
                "", ""
              ].join("\r\n")
              client.print response
              client.close
              next
            end
            
            # 4. JSON Body 수신 (Content-Length 기반)
            body = ""
            if headers['content-length']
              content_length = headers['content-length'].to_i
              body = client.read(content_length) if content_length > 0
            end
            
            # 5. 브라우저로 200 OK 회신 (브라우저 무한 로딩 및 타임아웃 방지)
            response_body = '{"success":true,"message":"Data successfully received by SketchUp plugin"}'
            response = [
              "HTTP/1.1 200 OK",
              "Access-Control-Allow-Origin: *",
              "Access-Control-Allow-Methods: POST, GET, OPTIONS",
              "Access-Control-Allow-Headers: Content-Type",
              "Content-Type: application/json",
              "Content-Length: #{response_body.bytesize}",
              "Connection: close",
              "",
              response_body
            ].join("\r\n")
            
            client.print response
            client.close
            
            # 6. POST 데이터 파싱 후 메인 스레드에 작업 위임
            if request_line && request_line.start_with?("POST") && !body.empty?
              begin
                parsed_data = JSON.parse(body)
                
                # SketchUp 화면 드로잉은 무조건 UI 메인 스레드에서 돌아야 하므로 타이머를 활용합니다.
                UI.start_timer(0.1, false) do
                  begin
                    AIArchitectServer.build_mass(parsed_data)
                  rescue => build_err
                    puts "렌더링 오류 (백트레이스):\n#{build_err.backtrace.join("\n")}"
                    UI.messagebox("모델 렌더링 중 치명적인 오류가 발생했습니다!\n오류: #{build_err.message}")
                  end
                end
              rescue => e
                puts "JSON 파싱 오류: #{e.message}"
              end
            end
            
          rescue => e
            puts "서버 요청 처리 중 예기치 않은 오류: #{e.message}" unless e.message.include?("closed")
          end
        end
      end
    rescue => e
      UI.messagebox("서버 시작 실패! 시작 전 3000번 포트가 사용 중인지 확인하세요.\n에러: #{e.message}")
    end
  end

  def self.stop_server
    @server_running = false
    @server.close if @server
    if @server_thread && @server_thread.alive?
      @server_thread.kill
    end
    UI.messagebox("⏹ AI Architect 로컬 서버를 중지했습니다.")
  end

  def self.build_mass(data)
    model = Sketchup.active_model
    entities = model.active_entities
    
    # 작업 되돌리기(Ctrl+Z)를 위한 트랜잭션 단위 묶음
    model.start_operation('AI 대안 모델 단위 생성', true)
    
    # 새 모델 그룹 생성
    alt_name = data['buildingInfo']['selectedAlternative']
    group = entities.add_group
    group.name = "AI 설계 매스 - #{alt_name} (#{Time.now.strftime('%H:%M:%S')})"
    
    geom_data = data['buildingInfo']['geometryData']
    floors = data['buildingInfo']['floors'].to_i
    
    # ========================================================
    # 🐛 [오류 해결 1] 단위 환산 문제
    # 웹 앱의 단위는 미터기반, 스케치업 내부 데이터 저장 단위는 인치입니다.
    # Ruby .m 확장 메소드가 없는 경우를 대비해 확실한 상수곱(39.3700787)으로 직접 변환!
    # ========================================================
    to_inch_ratio = 39.3700787
    width = geom_data['massBaseWidthM'].to_f * to_inch_ratio
    depth = geom_data['massBaseDepthM'].to_f * to_inch_ratio
    height = geom_data['floorHeightM'].to_f * to_inch_ratio

    # 층별 매스 모델 생성 루프
    floors.times do |f|
      setback_factor = f > 2 ? 0.9 : 1.0 # 3층 이상 상단 셋백 연출
      w = width * setback_factor
      d = depth * setback_factor
      z = f * height # 현재 층의 바닥 Z위치
      
      pt1 = Geom::Point3d.new(-w/2, -d/2, z)
      pt2 = Geom::Point3d.new(w/2, -d/2, z)
      pt3 = Geom::Point3d.new(w/2, d/2, z)
      pt4 = Geom::Point3d.new(-w/2, d/2, z)
      
      face = group.entities.add_face(pt1, pt2, pt3, pt4)
      
      # 높이가 Z 축 0(평지) 일 경우 바닥면의 법선(Normal) 방향이 꼬여서 면이 뒤집히는 그래픽 버그 해결
      face.reverse! if face.normal.z < 0
      
      # 한 층고 높이만큼 위로 면을 밀어올려(PushPull) 3D 입체화
      face.pushpull(height, true)
    end
    
    model.commit_operation
    Sketchup.send_action("viewZoomExtents:")
    
    puts "✅ 성공적으로 모델 구현 완료: #{alt_name} (#{floors}층)"
  end
end

unless file_loaded?(__FILE__)
  menu = UI.menu('Plugins')
  submenu = menu.add_submenu('AI Architect 로컬 통신')
  submenu.add_item('서버 시작하기 (웹 수신 대기)') { AIArchitectServer.start_server }
  submenu.add_item('서버 중지') { AIArchitectServer.stop_server }
  file_loaded(__FILE__)
end

# 이 줄을 그대로 콘솔에 실행시키면 즉각적으로 서버가 백그라운드에서 동작합니다.
AIArchitectServer.start_server
