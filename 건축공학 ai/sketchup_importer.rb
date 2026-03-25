# sketchup_importer.rb
# SketchUp 루비 콘솔에 복사하여 붙여넣거나 Plugins 폴더에 넣어 실행하세요.
require 'sketchup.rb'
require 'net/http'
require 'json'

module AIArchitectImporter
  def self.import_design
    url = URI.parse('http://localhost:3000/latest')
    begin
      response = Net::HTTP.get_response(url)
      
      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        
        # 에러 메시지(404 No Data 등) 우아하게 처리
        if data['success'] == false
          UI.messagebox("오류: #{data['error']}")
          return
        end
        
        build_mass(data)
      else
        UI.messagebox("서버에서 데이터를 가져오지 못했습니다. (에러 코드: #{response.code})\n웹에서 먼저 'SketchUp 연동' 버튼을 클릭했는지 확인해주세요.")
      end
    rescue => e
      UI.messagebox("로컬 서버(http://localhost:3000)에 연결할 수 없습니다.\n먼저 Node.js 서버 파일(server.js)을 실행해주세요.\n\n상세 에러: #{e.message}")
    end
  end

  def self.build_mass(data)
    model = Sketchup.active_model
    model.start_operation('AI 대안 매스 생성', true)
    
    entities = model.active_entities
    
    # 데이터를 그룹으로 묶기
    group = entities.add_group
    group.name = "AI 모델 - #{data['buildingInfo']['selectedAlternative']}"
    
    geom_data = data['buildingInfo']['geometryData']
    floors = data['buildingInfo']['floors'].to_i
    
    # Json 에는 M (미터) 단위로 담겨 있으므로 SketchUp 내부 단위(inch)로 변환
    width_m = geom_data['massBaseWidthM'].to_f
    depth_m = geom_data['massBaseDepthM'].to_f
    floor_height_m = geom_data['floorHeightM'].to_f
    
    width = width_m.m
    depth = depth_m.m
    height = floor_height_m.m

    # 층별 매스 박스 생성
    floors.times do |f|
      # 웹 화면의 셋백 로직 동일하게 반영 (3층 이상일 때 셋백)
      setback_factor = f > 2 ? 0.9 : 1.0 
      w = width * setback_factor
      d = depth * setback_factor
      
      z = f * height
      
      pt1 = Geom::Point3d.new(-w/2, -d/2, z)
      pt2 = Geom::Point3d.new(w/2, -d/2, z)
      pt3 = Geom::Point3d.new(w/2, d/2, z)
      pt4 = Geom::Point3d.new(-w/2, d/2, z)
      
      # 면 생성
      face = group.entities.add_face(pt1, pt2, pt3, pt4)
      
      # 반전 방지 처리 (Z=0일 때 아랫면 방향 이슈)
      face.reverse! if face.normal.z < 0
      
      # 층고(height)만큼 위로 돌출시켜 박스 생성
      face.pushpull(height, true)
    end
    
    model.commit_operation
    
    # 생성된 부분을 전체적으로 볼 수 있도록 줌 익스텐트
    Sketchup.send_action("viewZoomExtents:")
    
    UI.messagebox("성공적으로 #{data['buildingInfo']['selectedAlternative']} 모델을 빌드했습니다!\n- 층수: #{floors}층\n- 용도: #{data['buildingInfo']['use']}\n\n로컬서버를 통한 연동이 성공했습니다.")
  end
end

# SketchUp 상단 "Extensions(확장)" 메뉴에 등록
unless file_loaded?(__FILE__)
  menu = UI.menu('Plugins')
  menu.add_item('AI 건축 대안 불러오기 (Local Server)') {
    AIArchitectImporter.import_design
  }
  file_loaded(__FILE__)
end
